require "rails_helper"

RSpec.describe AiConcierge::Orchestration::Booking::MonthSegmentReader do
  it "reads English month segments" do
    examples = {
      "early" => %w[early],
      "mid" => %w[mid],
      "late" => %w[late]
    }

    examples.each do |segment, messages|
      messages.each { |message| expect(described_class.new(message).call).to eq(segment), message }
    end
  end

  it "reads natural English month segments" do
    examples = {
      "early" => [ "beginning of the month", "start of next month", "beginning of September" ],
      "mid" => [ "middle of the month", "middle part", "middle of September" ],
      "late" => [ "end month", "end of next month", "last part", "end of September" ]
    }

    examples.each do |segment, messages|
      messages.each { |message| expect(described_class.new(message).call).to eq(segment), message }
    end
  end

  it "reads Malay and Chinese month segments" do
    examples = {
      "early" => [ "awal bulan", "月初" ],
      "mid" => [ "pertengahan bulan", "月中" ],
      "late" => [ "hujung bulan", "akhir bulan", "月底", "月末" ]
    }

    examples.each do |segment, messages|
      messages.each { |message| expect(described_class.new(message).call).to eq(segment), message }
    end
  end

  it "returns nil for conflicting month segments" do
    expect(described_class.new("early or end of the month").call).to be_nil
  end

  it "does not invent a segment" do
    expect(described_class.new("next month").call).to be_nil
  end
end
