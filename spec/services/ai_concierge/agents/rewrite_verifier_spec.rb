# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiConcierge::Agents::RewriteVerifier do
  def verify(template, candidate, protected_names: [])
    described_class.new(template: template, candidate: candidate, protected_names: protected_names)
  end

  let(:quote) do
    [
      "Great, I've prepared your booking quote:",
      "- Date: *21 August 2026 - 23 August 2026*",
      "- Total: *RM 1,240.00*",
      "",
      "Please note that the quotation link will expire at 11:30 PM.",
      "Quotation link:",
      "https://wastays.test/quotes/abc123"
    ].join("\n")
  end

  it "passes a rewrite that only changed the words" do
    candidate = quote.sub("Great, I've prepared your booking quote:", "Wonderful news -- your quote is ready!")

    expect(verify(quote, candidate).call).to eq(candidate)
  end

  it "passes a translation that changed the month name" do
    candidate = quote.sub("21 August 2026 - 23 August 2026", "21 Ogos 2026 - 23 Ogos 2026")

    expect(verify(quote, candidate).call).to eq(candidate)
  end

  it "refuses a rewrite that moved a digit in the total" do
    checker = verify(quote, quote.sub("1,240.00", "1,204.00"))

    expect(checker.call).to be_nil
    expect(checker.failure).to eq(:numbers)
  end

  it "refuses a rewrite that dropped the quotation link" do
    checker = verify(quote, quote.sub("https://wastays.test/quotes/abc123", "the link above"))

    expect(checker.call).to be_nil
    expect(checker.failure).to eq(:urls)
  end

  it "refuses a rewrite that relabelled the link" do
    checker = verify(quote, quote.sub("https://wastays.test/quotes/abc123", "https://wastays.test/quotes"))

    expect(checker.call).to be_nil
    expect(checker.failure).to eq(:urls)
  end

  it "does not care whether the link ends a sentence" do
    template = "Book here: https://wastays.test/quotes/abc123"
    candidate = "Anda boleh menempah di sini: https://wastays.test/quotes/abc123."

    expect(verify(template, candidate).call).to eq(candidate)
  end

  it "refuses a rewrite that changed the currency in front of a price" do
    checker = verify("Your total is RM 480.00.", "Jumlah anda USD 480.00.")

    expect(checker.call).to be_nil
    expect(checker.failure).to eq(:currency)
  end

  it "refuses a number spelled out in words" do
    checker = verify("How many guests should I check for on August 21?", "Untuk berapa orang tetamu pada dua puluh satu Ogos?")

    expect(checker.call).to be_nil
    expect(checker.failure).to eq(:numbers)
  end

  it "leaves a hotel's own initials alone" do
    template = "Welcome to KLCC Suites! Check-in starts at 3:00 PM."
    candidate = "Selamat datang ke KLCC Suites! Daftar masuk bermula 3:00 PM."

    expect(verify(template, candidate).call).to eq(candidate)
  end

  it "refuses a translated room type name" do
    checker = verify(
      "For *Garden Prestige Suite* on 28 August 2026, which rate plan would you like?",
      "Untuk *Suite Taman Prestij* pada 28 Ogos 2026, pelan kadar mana yang anda mahu?",
      protected_names: [ "Garden Prestige Suite", "Standard Rate" ]
    )

    expect(checker.call).to be_nil
    expect(checker.failure).to eq(:names)
  end

  it "allows a translated reply that leaves the room name standing" do
    candidate = "Untuk *Garden Prestige Suite* pada 28 Ogos 2026, pelan kadar mana yang anda mahu?"
    checker = verify(
      "For *Garden Prestige Suite* on 28 August 2026, which rate plan would you like?",
      candidate,
      protected_names: [ "Garden Prestige Suite", "Standard Rate" ]
    )

    expect(checker.call).to eq(candidate)
  end

  it "does not demand names the reply never used" do
    candidate = "Baik, beritahu saya jika perlu apa-apa."

    expect(verify("No problem, please let me know if you need anything.", candidate, protected_names: [ "Ocean Villa King" ]).call).to eq(candidate)
  end

  it "passes a reply with nothing to protect" do
    expect(verify("No problem, please let me know if you need anything.", "Baik, beritahu saya jika perlu apa-apa.").call).to be_present
  end
end
