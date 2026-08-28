require "rails_helper"

RSpec.describe PublicUI::Chat::QuickReplies, type: :component do
  let(:suggestion) do
    Concierge::ChatInputPresenter::Suggestion.new(
      label: "Find a room",
      kind: :message,
      value: "I want to find a room."
    )
  end

  it "renders optional message, staff, and composer-focus actions" do
    suggestions = [
      suggestion,
      Concierge::ChatInputPresenter::Suggestion.new(label: "Ask the hotel team", kind: :agent),
      Concierge::ChatInputPresenter::Suggestion.new(label: "Ask another question", kind: :focus)
    ]

    render_inline(described_class.new(
      suggestions: suggestions,
      message_url: "/chat",
      agent_url: "/chat/agent"
    ))

    expect(page).to have_button("Find a room")
    expect(page).to have_css("form[action='/chat'] input[name='message'][value='I want to find a room.']", visible: :hidden)
    expect(page).to have_css("form[action='/chat/agent'] input[name='reason'][value='booking_support']", visible: :hidden)
    expect(page).to have_button("Ask another question")
  end
end
