require "rails_helper"

# The keyboard half of the chat, which only exists once JavaScript is running:
# the box sends on Enter, and everything else on the page must stay out of the
# way of that.
RSpec.describe "Concierge chat keyboard", type: :system do
  let(:feature_group) { create(:feature_group) }
  let(:ai_concierge_page_feature) { create(:feature, feature_group: feature_group, slug: "ai_concierge_page") }
  let(:plan) { create(:plan) }
  let(:hotel) { create(:hotel, status: "live", concierge_enabled: true, plan: plan) }

  before do
    driven_by(:cuprite, options: { window_size: [ 1400, 1000 ] })
    create(:plan_feature, plan: plan, feature: ai_concierge_page_feature, enabled: true)
  end

  def open_chat = visit(concierge_chat_path(hotel))

  def send_message(text)
    find(".public-chat__input").set(text)
    find(".public-chat__input").send_keys(:enter)
  end

  it "sends the message the guest typed" do
    open_chat

    send_message("Do you have parking?")

    expect(page).to have_css(".public-chat__bubble", text: "Do you have parking?")
    expect(Conversation.last.messages.last.body).to eq("Do you have parking?")
  end

  it "empties the box afterwards without taking the focus off it" do
    open_chat

    send_message("Do you have parking?")

    expect(page).to have_css(".public-chat__bubble", text: "Do you have parking?")
    expect(find(".public-chat__input").value).to eq("")
  end

  # The regression that earned this file. Enter used to submit whichever form
  # came first in the panel, and button_to gives every menu item one of its own
  # -- the bar being above the box, that was "clear conversation". Submitting a
  # form without its button also skips the confirm hanging off the button, so a
  # guest pressing Enter had their thread closed without being asked.
  it "does not touch the conversation menu's actions" do
    open_chat
    send_message("First question")
    expect(page).to have_css(".public-chat__bubble", text: "First question")

    send_message("Second question")

    expect(page).to have_css(".public-chat__bubble", text: "Second question")
    expect(Conversation.count).to eq(1)
    expect(Conversation.last).to be_open
    expect(Conversation.last.messages.where(sender_role: "guest").count).to eq(2)
  end

  it "still breaks the line on Shift+Enter" do
    open_chat

    find(".public-chat__input").set("First line")
    find(".public-chat__input").send_keys(%i[shift enter])

    expect(page).to have_css(".public-chat__input")
    expect(ProspectMessage.count).to eq(0)
  end

  # Clearing is reachable, and only from the menu.
  it "clears the conversation when the menu item is chosen" do
    open_chat
    send_message("Do you have parking?")
    expect(page).to have_css(".public-chat__bubble", text: "Do you have parking?")

    accept_confirm do
      find(".public-menu__trigger").click
      click_button("Clear conversation")
    end

    expect(page).to have_no_css(".public-chat__bubble", text: "Do you have parking?")
    expect(Conversation.last).not_to be_open
  end
end
