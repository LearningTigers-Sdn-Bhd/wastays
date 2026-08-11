require "rails_helper"

RSpec.describe ChannelManagers::ConvertBookingCurrency do
  let(:hotel) { create(:hotel, default_currency: "MYR") }
  let(:booking_data) do
    {
      hotel: hotel,
      currency: "USD",
      total_amount: 100,
      rooms: [
        { amount: 60, quantity: 1 },
        { amount: 40, quantity: 1 }
      ]
    }
  end

  it "converts booking and room amounts into the hotel currency" do
    create(:exchange_rate, base_currency: "USD", currency_code: "MYR", rate: 4.1)

    result = described_class.new(booking_data: booking_data).call

    expect(result).to be_success
    expect(result.booking_data).to include(currency: "MYR", total_amount: 410.to_d)
    expect(result.booking_data[:rooms].pluck(:amount)).to eq([ 246.to_d, 164.to_d ])
    expect(result.booking_data[:currency_conversion]).to include(
      "source_currency" => "USD",
      "target_currency" => "MYR",
      "rate" => "4.1",
      "source_total_amount" => "100.0",
      "converted_total_amount" => "410.0"
    )
  end

  it "keeps the converted room amounts adding up to the converted total" do
    create(:exchange_rate, base_currency: "USD", currency_code: "MYR", rate: 4.1)
    data = booking_data.merge(
      total_amount: 100,
      rooms: [ { amount: 33.33 }, { amount: 33.33 }, { amount: 33.34 } ]
    )

    result = described_class.new(booking_data: data).call

    amounts = result.booking_data[:rooms].pluck(:amount)
    expect(amounts.sum).to eq(result.booking_data[:total_amount])
    expect(amounts).to eq([ 136.65.to_d, 136.65.to_d, 136.7.to_d ])
  end

  it "leaves same-currency booking data unchanged" do
    data = booking_data.merge(currency: "MYR")

    result = described_class.new(booking_data: data).call

    expect(result).to be_success
    expect(result.booking_data).to include(currency: "MYR", total_amount: 100)
    expect(result.booking_data).not_to have_key(:currency_conversion)
  end

  it "fails when no managed exchange rate can resolve the currency pair" do
    result = described_class.new(booking_data: booking_data).call

    expect(result).not_to be_success
    expect(result.message).to eq("Missing exchange rate from USD to MYR")
  end
end
