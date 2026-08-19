# frozen_string_literal: true

require "rails_helper"

RSpec.describe PublicUI::Menu, type: :component do
  it "keeps its actions closed and announced until the trigger is pressed" do
    render_inline(described_class.new(label: "Conversation options")) do |menu|
      menu.with_item(href: "/concierge/aurora/chat") { "Clear conversation" }
    end

    expect(page).to have_css("button.public-menu__trigger[aria-haspopup='menu'][aria-expanded='false'][aria-label='Conversation options']")
    expect(page).to have_css(".public-menu__list[role='menu'][hidden]", visible: :all)
    expect(page).to have_css("[role='menuitem']", text: "Clear conversation", visible: :all)
  end

  # Anything that changes something has to be a form: a menu of links would put
  # "clear my conversation" one prefetch away.
  it "posts an action that changes something rather than linking to it" do
    render_inline(described_class.new(label: "Conversation options")) do |menu|
      menu.with_item(href: "/concierge/aurora/chat", method: :delete, confirm: "Sure?") { "Clear conversation" }
    end

    expect(page).to have_css("form[action='/concierge/aurora/chat'][method='post']", visible: :all)
    expect(page).to have_css("input[name='_method'][value='delete']", visible: :all)
    expect(page).to have_css("[role='menuitem'][data-turbo-confirm='Sure?']", visible: :all)
  end

  it "marks an action the guest cannot undo" do
    render_inline(described_class.new(label: "Conversation options")) do |menu|
      menu.with_item(href: "/x", method: :delete, danger: true) { "Clear conversation" }
    end

    expect(page).to have_css("[role='menuitem'][data-danger='true']", visible: :all)
  end

  it "closes itself when an item is chosen" do
    render_inline(described_class.new(label: "Conversation options")) do |menu|
      menu.with_item(href: "/x") { "Clear conversation" }
    end

    expect(page).to have_css("[role='menuitem'][data-action='public-menu#close']", visible: :all)
  end
end
