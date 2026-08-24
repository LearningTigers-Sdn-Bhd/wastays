# frozen_string_literal: true

require "rails_helper"

# The stylist, run over a whole booking rather than over one sentence.
#
# The unit specs prove the verifier's rules. This proves the thing those rules
# exist for: the ladder that ends in a payable quote still ends in the same
# payable quote once a model has had the last word on how it reads.
RSpec.describe "AI concierge replies in the guest's language", :ai_concierge_eval do
  let(:fixture) { AiConciergeEval::ConversationFixture.all.find { |candidate| candidate.id == "timing_to_quote" } }

  def replies(stylist:)
    [].tap do |collected|
      run_fixture(fixture, stylist: stylist) { |_turn, outcome, _index| collected << outcome.reply }
    end
  end

  def conversation = Conversation.order(:id).last

  it "sends the rewrite when it kept everything the guest can act on" do
    collected = replies(stylist: { transform: ->(template) { "Baik!\n\n#{template}" }, language: "ms" })

    quote = collected.compact.find { |reply| reply.include?("Quotation link:") }
    expect(quote).to start_with("Baik!")
    expect(quote).to match(%r{https?://\S+})
    expect(conversation.language).to eq("ms")
  end

  # The fixture that has to script the model getting it wrong: a rewrite that
  # reads beautifully, quotes a price nobody offered and points the guest at a
  # link that does not exist. Delete RewriteVerifier and this goes red.
  it "sends the quote Ruby wrote when the rewrite invented a different one" do
    mangled = "Tempahan anda sudah siap! Jumlah hanya RM 1.00 sahaja. Klik pautan di atas untuk membayar."

    collected = replies(stylist: { text: mangled, language: "ms" })

    expect(collected.compact).to all(satisfy { |reply| reply.exclude?("RM 1.00") })
    quote = collected.compact.find { |reply| reply.include?("Quotation link:") }
    expect(quote).to match(%r{https?://\S+})

    # The rewrite was refused, not skipped: the thread still knows the guest is
    # writing in Malay, and the next turn will try again.
    expect(conversation.language).to eq("ms")
  end
end
