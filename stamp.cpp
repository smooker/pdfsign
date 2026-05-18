// stamp.cpp -- append black-bar e-signature banner to top of every page.
// Uses libqpdf; preserves original content byte-level (no clone, no re-render).
//
// Usage: stamp <input.pdf> <output.pdf> <signer> <issuer> <serial>

#include <qpdf/QPDF.hh>
#include <qpdf/QPDFWriter.hh>
#include <qpdf/QPDFPageDocumentHelper.hh>
#include <qpdf/QPDFPageObjectHelper.hh>
#include <qpdf/QPDFObjectHandle.hh>

#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <sstream>
#include <string>

// 1 mm = 2.8346 PDF points
static const double MM = 2.8346;
static const double BAR_MM = 5.0;
static const double FONT_PT = 6.0;

// Escape a UTF-8 string for use inside a PDF literal string "(...)".
// Drops bytes outside WinAnsi printable range; Helvetica + WinAnsiEncoding
// does not support non-Latin. Caller must ensure ASCII-ish input.
static std::string pdf_string_literal(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    out.push_back('(');
    for (unsigned char c : s) {
        if (c == '(' || c == ')' || c == '\\') {
            out.push_back('\\');
            out.push_back(c);
        } else if (c >= 0x20 && c < 0x7f) {
            out.push_back(c);
        }
        // skip non-printable / non-ASCII silently
    }
    out.push_back(')');
    return out;
}

static std::string now_iso() {
    char buf[32];
    std::time_t t = std::time(nullptr);
    std::tm tm{};
    localtime_r(&t, &tm);
    std::strftime(buf, sizeof(buf), "%Y-%m-%d %H:%M:%S", &tm);
    return std::string(buf);
}

static void ensure_helvetica_font(QPDF& pdf, QPDFPageObjectHelper& page) {
    QPDFObjectHandle page_dict = page.getObjectHandle();
    QPDFObjectHandle resources = page.getAttribute("/Resources", true);
    if (!resources.isDictionary()) {
        resources = QPDFObjectHandle::newDictionary();
        page_dict.replaceKey("/Resources", resources);
    } else {
        // Make sure we modify a dict owned by THIS page, not inherited
        // from /Pages. If inherited, copy it down.
        if (!page_dict.hasKey("/Resources")) {
            QPDFObjectHandle local = QPDFObjectHandle::newDictionary();
            for (auto const& k : resources.getKeys()) {
                local.replaceKey(k, resources.getKey(k));
            }
            resources = local;
            page_dict.replaceKey("/Resources", resources);
        }
    }
    QPDFObjectHandle fonts = resources.getKey("/Font");
    if (!fonts.isDictionary()) {
        fonts = QPDFObjectHandle::newDictionary();
        resources.replaceKey("/Font", fonts);
    }
    if (!fonts.hasKey("/PDFSIGNF1")) {
        QPDFObjectHandle font = QPDFObjectHandle::newDictionary();
        font.replaceKey("/Type", QPDFObjectHandle::newName("/Font"));
        font.replaceKey("/Subtype", QPDFObjectHandle::newName("/Type1"));
        font.replaceKey("/BaseFont", QPDFObjectHandle::newName("/Helvetica-Bold"));
        font.replaceKey("/Encoding", QPDFObjectHandle::newName("/WinAnsiEncoding"));
        fonts.replaceKey("/PDFSIGNF1", pdf.makeIndirectObject(font));
    }
}

int main(int argc, char** argv) {
    if (argc < 6) {
        std::fprintf(stderr,
            "Usage: %s <input.pdf> <output.pdf> <signer> <issuer> <serial>\n",
            argv[0]);
        return 1;
    }
    const char* in_path  = argv[1];
    const char* out_path = argv[2];
    std::string signer   = argv[3];
    std::string issuer   = argv[4];
    std::string serial   = argv[5];

    std::string banner_text =
        "e-sign (pdfsign) by " + signer +
        "  |  " + issuer +
        "  |  SN: " + serial +
        "  |  " + now_iso();

    try {
        QPDF pdf;
        pdf.processFile(in_path);

        QPDFPageDocumentHelper dh(pdf);
        auto pages = dh.getAllPages();
        int n = 0;
        for (auto& page : pages) {
            // MediaBox -> [x0 y0 x1 y1]
            QPDFObjectHandle mb = page.getAttribute("/MediaBox", true);
            if (!mb.isArray() || mb.getArrayNItems() < 4) {
                std::fprintf(stderr, "page %d: missing MediaBox\n", n);
                return 2;
            }
            double x0 = mb.getArrayItem(0).getNumericValue();
            double y0 = mb.getArrayItem(1).getNumericValue();
            double x1 = mb.getArrayItem(2).getNumericValue();
            double y1 = mb.getArrayItem(3).getNumericValue();
            double w = x1 - x0;
            double h = y1 - y0;
            double bar_pt = BAR_MM * MM;            // ~14.17
            double text_x = x0 + 2.0 * MM;          // 2 mm left margin
            double text_y = y1 - bar_pt + 1.5 * MM; // baseline inside bar

            std::ostringstream cs;
            cs.setf(std::ios::fixed);
            cs.precision(3);
            cs << "\nq\n"
               << "0 0 0 rg\n"
               << x0 << " " << (y1 - bar_pt) << " " << w << " " << bar_pt
               << " re f\n"
               << "1 1 1 rg\n"
               << "BT /PDFSIGNF1 " << FONT_PT << " Tf "
               << text_x << " " << text_y << " Td "
               << pdf_string_literal(banner_text) << " Tj ET\n"
               << "Q\n";

            QPDFObjectHandle stream =
                QPDFObjectHandle::newStream(&pdf, cs.str());
            // false = append (after existing content)
            page.addPageContents(stream, false);

            ensure_helvetica_font(pdf, page);
            ++n;
        }

        QPDFWriter w(pdf, out_path);
        w.setStaticID(false);
        w.write();
        std::fprintf(stderr, "Stamped: %s (%d pages)\n", out_path, n);
        return 0;
    } catch (std::exception& e) {
        std::fprintf(stderr, "stamp: %s\n", e.what());
        return 3;
    }
}
