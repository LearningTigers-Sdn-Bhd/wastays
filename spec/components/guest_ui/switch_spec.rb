# frozen_string_literal: true

require "rails_helper"

RSpec.describe GuestUI::Switch, type: :component do
  def render_switch(**options)
    render_inline(described_class.new(
      label: "Do not disturb",
      url: "/stay/dnd",
      **options
    ))
  end

  # The state lives on the server. A guest turns this on, closes the page, and
  # opens it on a second device, and housekeeping reads a third copy on the
  # floor sheet -- a switch that flips in the browser first is a switch that can
  # disagree with the room.
  it "posts rather than holding a state of its own" do
    render_switch

    expect(page).to have_css("form[action='/stay/dnd'] button.guest-switch[type='submit']")
    expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
  end

  it "is a switch, and says which way it is set" do
    render_switch(checked: true)

    expect(page).to have_css("button[role='switch'][aria-checked='true']")
  end

  it "says so when it is off" do
    render_switch(checked: false)

    expect(page).to have_css("button[role='switch'][aria-checked='false']")
  end

  it "reads its label and its hint out as the name of the control" do
    render_switch(hint: "Housekeeping will keep away from your room.")

    expect(page).to have_css(".guest-switch__label", text: "Do not disturb")
    expect(page).to have_css(".guest-switch__hint", text: "Housekeeping will keep away from your room.")
  end

  it "leaves the hint out when there is none" do
    render_switch

    expect(page).to have_no_css(".guest-switch__hint")
  end

  # The state is already on the control as aria-checked. A screen reader that
  # read the track as well would report it twice.
  it "hides the track from a screen reader" do
    render_switch

    expect(page).to have_css(".guest-switch__track[aria-hidden='true'] .guest-switch__thumb")
  end

  it "takes a method other than patch" do
    render_switch(method: :post)

    expect(page).to have_css("form[method='post']")
    expect(page).to have_no_css("input[name='_method']", visible: :all)
  end

  it "asks Turbo to confirm first when told to" do
    render_switch(confirm: "Keep housekeeping away all day?")

    expect(page).to have_css("button[data-turbo-confirm='Keep housekeeping away all day?']")
  end

  it "can be turned off entirely" do
    render_switch(disabled: true)

    expect(page).to have_css("button.guest-switch[disabled]")
  end
end
