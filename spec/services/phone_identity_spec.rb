require "rails_helper"

RSpec.describe PhoneIdentity do
  describe ".variants" do
    it "normalizes common Malaysian phone formats consistently" do
      expect(described_class.variants("011-234 5678")).to eq([ "0112345678", "60112345678", "+60112345678" ])
      expect(described_class.variants("+60112345678")).to eq([ "+60112345678", "60112345678", "0112345678" ])
    end
  end

  describe ".find_guest" do
    it "matches guests across supported phone variants" do
      guest = create(:guest, phone: "+60123456789")

      expect(described_class.find_guest("0123456789")).to eq(guest)
    end
  end
end
