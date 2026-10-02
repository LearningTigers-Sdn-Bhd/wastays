require "rails_helper"

RSpec.describe Reports::AmountInWords do
  it "writes a whole ringgit amount" do
    expect(described_class.call(2280, currency: "MYR")).to eq("Two thousand two hundred and eighty ringgit only")
  end

  it "adds sen when the amount has cents" do
    expect(described_class.call(BigDecimal("1300.50"), currency: "MYR"))
      .to eq("One thousand three hundred ringgit and fifty sen only")
  end

  it "joins a small remainder after a scale with and" do
    expect(described_class.call(1005, currency: "MYR")).to eq("One thousand and five ringgit only")
  end

  it "writes millions and hyphenated tens" do
    expect(described_class.call(1_234_567, currency: "MYR"))
      .to eq("One million two hundred and thirty-four thousand five hundred and sixty-seven ringgit only")
  end

  it "writes zero" do
    expect(described_class.call(0, currency: "MYR")).to eq("Zero ringgit only")
  end

  it "names other currencies by code" do
    expect(described_class.call(BigDecimal("12.05"), currency: "USD")).to eq("Twelve USD and five cents only")
  end
end
