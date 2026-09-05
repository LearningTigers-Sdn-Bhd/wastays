require "rails_helper"

RSpec.describe EInvoice::DocumentBuilder, type: :service do
  describe "#build" do
    let(:hotel) { create(:hotel, default_currency: "MYR", tin: "C9988776655", ssm_number: "202399887766") }
    let!(:e_invoice_setting) do
      create(:e_invoice_setting, hotel: hotel)
    end
    let(:booking) do
      create(:booking,
        hotel: hotel,
        booking_quote: nil,
        guest_name: "John Doe",
        guest_email: "john@example.com",
        guest_phone: "+60123456789",
        guest_city: "Kuala Lumpur",
        guest_state_code: "14",
        guest_address_country: "Malaysia",
        guest_tin: "IG12345678901",
        guest_document_type: "passport",
        check_in: 2.days.ago,
        check_out: Date.today,
        total_amount: 424.00,
        currency: "MYR"
      ).tap do |created_booking|
        created_booking.guest_government_id = "A12345678"
      end
    end
    let!(:booking_room) do
      create(:booking_room,
        booking: booking,
        subtotal: 400.00
      )
    end

    before do
      allow(Rails.application.credentials).to receive(:myinvois).and_return(
        double(
          to_h: {
            tin: "C1234567890",
            brn: "202301012345",
            name: "Jesselton Pixel Sdn Bhd",
            phone: "+60111234567",
            email: "finance@wastays.com",
            city: "Kota Kinabalu",
            postal_code: "88000",
            state_code: "12",
            address: "123 Street"
          }
        )
      )
    end

    subject { described_class.new(booking).build }

    it "returns a hash with format, document, documentHash, and codeNumber" do
      expect(subject).to include(
        format: "JSON",
        codeNumber: booking.confirmation_token
      )
      expect(subject[:document]).to be_a(String)
      expect(subject[:documentHash]).to be_a(String)
    end

    it "builds a UBL payload where line extension amount matches the math requirement" do
      decoded_json = JSON.parse(Base64.strict_decode64(subject[:document]))
      invoice = decoded_json["Invoice"].first
      line = invoice["InvoiceLine"].first

      quantity = line["InvoicedQuantity"].first["_"].to_f
      price_amount = line["Price"].first["PriceAmount"].first["_"].to_f
      line_extension_amount = line["LineExtensionAmount"].first["_"].to_f

      # LHDN math constraint validation: LineExtensionAmount = InvoiceQuantity * PriceAmount
      expect(line_extension_amount).to eq(quantity * price_amount)
      expect(line.dig("InvoicedQuantity", 0, "unitCode")).to eq("C62")
    end

    it "uses official MyInvois JSON field names for identity and quantity" do
      decoded_json = JSON.parse(Base64.strict_decode64(subject[:document]))
      invoice = decoded_json["Invoice"].first
      supplier = invoice.dig("AccountingSupplierParty", 0, "Party", 0)
      buyer = invoice.dig("AccountingCustomerParty", 0, "Party", 0)
      line = invoice["InvoiceLine"].first

      expect(line).to include("InvoicedQuantity")
      expect(line).not_to include("InvoiceQuantity")

      expect(supplier.dig("PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq(hotel.name)
      expect(buyer.dig("PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq("John Doe")
    end

    it "includes buyer identity and ISO country metadata expected by MyInvois" do
      decoded_json = JSON.parse(Base64.strict_decode64(subject[:document]))
      buyer = decoded_json.dig("Invoice", 0, "AccountingCustomerParty", 0, "Party", 0)
      buyer_ids = buyer.fetch("PartyIdentification")
      country = buyer.dig("PostalAddress", 0, "Country", 0, "IdentificationCode", 0)
      city = buyer.dig("PostalAddress", 0, "CityName", 0, "_")
      state_code = buyer.dig("PostalAddress", 0, "CountrySubentityCode", 0, "_")

      expect(buyer_ids.first.dig("ID", 0, "_")).to eq("IG12345678901")
      expect(buyer_ids.second.dig("ID", 0, "schemeID")).to eq("PASSPORT")
      expect(buyer_ids.second.dig("ID", 0, "_")).to eq("A12345678")
      expect(city).to eq("Kuala Lumpur")
      expect(state_code).to eq("14")
      expect(country).to include("_" => "MYS", "listID" => "ISO3166-1", "listAgencyID" => "6")
    end

    it "builds buyer details from the supplied immutable snapshot" do
      snapshot = EInvoice::BuyerSnapshot.capture(booking).deep_merge(
        "name" => "Snapshot Guest",
        "contact_email" => "snapshot@example.com",
        "billing_address" => {
          "address_line1" => "8 Snapshot Road",
          "city" => "Kuching",
          "state_code" => "13",
          "postal_code" => "93000",
          "country" => "Malaysia",
          "country_code" => "MYS"
        }
      )
      booking.update!(guest_name: "Changed Guest", guest_city: "Johor Bahru", guest_state_code: "01")

      result = described_class.new(booking, buyer_snapshot: snapshot).build
      buyer = JSON.parse(Base64.strict_decode64(result[:document]))
        .dig("Invoice", 0, "AccountingCustomerParty", 0, "Party", 0)

      expect(buyer.dig("PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq("Snapshot Guest")
      expect(buyer.dig("PostalAddress", 0, "CityName", 0, "_")).to eq("Kuching")
      expect(buyer.dig("PostalAddress", 0, "CountrySubentityCode", 0, "_")).to eq("13")
      expect(buyer.dig("Contact", 0, "ElectronicMail", 0, "_")).to eq("snapshot@example.com")
    end

    # WAStays is under the RM1m threshold and files nothing as itself, so the
    # hotel is the supplier even when WAStays took the guest's money.
    # LHDN rejects a backdated document. The payment date still decides which
    # month a guest may request in; it is not when the document was issued.
    it "issues the document now, not on the date the guest paid" do
      travel_to Time.zone.parse("2026-08-20 10:30:00") do
        decoded = JSON.parse(Base64.strict_decode64(described_class.new(booking).build[:document]))
        invoice = decoded.dig("Invoice", 0)

        expect(invoice.dig("IssueDate", 0, "_")).to eq("2026-08-20")
        expect(invoice.dig("IssueTime", 0, "_")).to match(/\A\d{2}:\d{2}:\d{2}Z\z/)
      end
    end

    it "uses the hotel as the supplier even for WAStays-collected bookings" do
      decoded_json = JSON.parse(Base64.strict_decode64(subject[:document]))
      supplier = decoded_json.dig("Invoice", 0, "AccountingSupplierParty", 0, "Party", 0)

      expect(supplier.dig("PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq(hotel.name)
      expect(supplier.dig("PartyIdentification", 0, "ID", 0, "_")).to eq("C9988776655")
    end

    context "when the hotel collected payment directly" do
      let(:booking) do
        create(:booking,
          :direct_hotel_payment,
          hotel: hotel,
          booking_quote: nil,
          guest_name: "John Doe",
          guest_email: "john@example.com",
          guest_phone: "+60123456789",
          guest_city: "Kuala Lumpur",
          guest_tin: "IG12345678901",
          guest_document_type: "passport",
          check_in: 2.days.ago,
          check_out: Date.today,
          total_amount: 424.00,
          currency: "MYR"
        ).tap do |created_booking|
          created_booking.guest_government_id = "A12345678"
        end
      end

      before { e_invoice_setting.update!(intermediary_enabled: true) }

      it "uses the hotel as the supplier" do
        decoded_json = JSON.parse(Base64.strict_decode64(subject[:document]))
        supplier = decoded_json.dig("Invoice", 0, "AccountingSupplierParty", 0, "Party", 0)

        expect(supplier.dig("PartyLegalEntity", 0, "RegistrationName", 0, "_")).to eq(hotel.name)
        expect(supplier.dig("PartyIdentification", 0, "ID", 0, "_")).to eq("C9988776655")
        expect(supplier.dig("PartyIdentification", 1, "ID", 0, "_")).to eq("202399887766")
      end
    end

    context "when booking has no rooms" do
      before { booking_room.destroy! }

      it "raises an argument error" do
        expect { described_class.new(booking).build }
          .to raise_error(ArgumentError, "Booking has no rooms")
      end
    end

    context "when booking has no guest city" do
      before { booking.update_columns(guest_city: nil) }

      it "raises an argument error" do
        expect { described_class.new(booking).build }
          .to raise_error(ArgumentError, "Booking guest city is required")
      end
    end

    # The hotel files under its own LHDN registration, so a document without a
    # setting to draw the supplier's identity from cannot be built - there is
    # no separate global credential to fall back to.
    context "when the hotel has no e-invoice setting" do
      it "raises an argument error" do
        unconfigured_hotel = create(:hotel, default_currency: "MYR")
        unconfigured_booking = create(:booking, hotel: unconfigured_hotel, booking_quote: nil, total_amount: 100.0)
        create(:booking_room, booking: unconfigured_booking, subtotal: 100.0)
        context = EInvoice::SubmissionContext::Context.new(
          booking: unconfigured_booking,
          hotel: unconfigured_hotel,
          setting: nil,
          fund_collector: "wastays",
          submission_mode: "taxpayer",
          supplier_name: nil,
          supplier_tin: nil,
          represented_taxpayer_tin: nil
        )

        expect { described_class.new(unconfigured_booking, context: context).build }
          .to raise_error(ArgumentError, "Hotel e-invoice setting is missing.")
      end
    end
  end
end
