require "rails_helper"

RSpec.describe AiConcierge::Matching::GreetingMatcher do
  subject(:matcher) { described_class.new(message: message) }

  it "matches standalone English, Malay, and Chinese greetings" do
    [ "hello", "Selamat pagi", "你好" ].each do |greeting|
      expect(described_class.new(message: greeting)).to be_standalone
    end
  end

  it "ignores case, punctuation, whitespace, and surrounding emoji" do
    expect(described_class.new(message: "  👋 HELLO!!! 😊 ")).to be_standalone
  end

  it "matches a wave emoji by itself" do
    expect(described_class.new(message: "👋🏽")).to be_standalone
  end

  it "does not capture a greeting that also states a purpose" do
    expect(described_class.new(message: "Hello, I want to book")).not_to be_standalone
    expect(described_class.new(message: "Hi, what time is check-in?")).not_to be_standalone
  end
end
