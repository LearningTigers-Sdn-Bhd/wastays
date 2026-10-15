# frozen_string_literal: true

require "rails_helper"

RSpec.describe HotelPortal::Reports::Exports::PdfTheme do
  let(:pdf) { Prawn::Document.new }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("WASTAYS_PDF_UNICODE_FONT_PATH").and_return(nil)
    allow(ENV).to receive(:[]).with("WASTAYS_PDF_UNICODE_BOLD_FONT_PATH").and_return(nil)
  end

  it "provides bundled Chinese glyphs in normal and bold styles" do
    described_class.configure_font(pdf)

    expect(pdf.font.family).to eq(described_class::TEXT_FAMILY)
    expect(pdf.fallback_fonts).to eq([ described_class::FALLBACK_FAMILY, described_class::SYMBOLS_FAMILY ])
    [ :normal, :bold ].each do |style|
      pdf.font(described_class::FALLBACK_FAMILY, style: style) do
        "入住时间下午三点。繁體中文，食物过敏：".each_char do |character|
          expect(pdf.font.glyph_present?(character)).to be(true), "Missing #{character} in #{style} Chinese fallback"
        end
      end
    end
  end

  it "provides checkbox glyphs for normal and bold text" do
    described_class.configure_font(pdf)

    [ :normal, :bold ].each do |style|
      pdf.font(described_class::SYMBOLS_FAMILY, style: style) do
        "☐☑□✓✔".each_char do |character|
          expect(pdf.font.glyph_present?(character)).to be(true), "Missing #{character} in #{style} symbols fallback"
        end
      end
    end
  end

  it "preserves explicit font overrides and uses the normal override when no bold override is supplied" do
    normal = described_class.font_dir.join("PublicSans-Regular.ttf").to_s
    bold = described_class.font_dir.join("PublicSans-Bold.ttf").to_s
    allow(ENV).to receive(:[]).with("WASTAYS_PDF_UNICODE_FONT_PATH").and_return(normal)

    expect(described_class.cjk_font_paths).to eq(normal: normal, bold: normal)

    allow(ENV).to receive(:[]).with("WASTAYS_PDF_UNICODE_BOLD_FONT_PATH").and_return(bold)
    expect(described_class.cjk_font_paths).to eq(normal: normal, bold: bold)
  end

  it "uses bundled fonts when the override does not exist" do
    allow(ENV).to receive(:[]).with("WASTAYS_PDF_UNICODE_FONT_PATH").and_return("/missing/unicode.ttf")

    expect(described_class.cjk_font_paths).to eq(
      normal: described_class.font_dir.join("NotoSansSC-Regular.ttf").to_s,
      bold: described_class.font_dir.join("NotoSansSC-Bold.ttf").to_s
    )
  end
end
