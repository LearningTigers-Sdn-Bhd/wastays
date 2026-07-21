# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Avatar", type: :system do
  before { visit_when_loaded "/system-design?only=avatar_preview" }

  it "renders the avatar showcase in both themes at Nova dimensions" do
    expect(page).to have_css("#avatar-preview-heading", text: "Avatar")
    expect(page).to have_css("[data-theme='panel-light'] .panel-avatar", minimum: 10)
    expect(page).to have_css("[data-theme='panel-dark'] .panel-avatar", minimum: 10)

    dimensions = page.evaluate_script(<<~JS)
      (() => {
        const section = document.getElementById("avatar-preview-heading").closest("section")
        const theme = section.querySelector("[data-theme='panel-light']")
        return ["sm", "default", "lg"].map(size => {
          const rect = theme.querySelector(`.panel-avatar[data-size="${size}"]`).getBoundingClientRect()
          return [Math.round(rect.width), Math.round(rect.height)]
        })
      })()
    JS

    expect(dimensions).to eq([ [ 24, 24 ], [ 32, 32 ], [ 40, 40 ] ])
  end

  it "reveals the fallback when an avatar image fails" do
    avatar = page.find("[data-testid='failed-avatar-panel-light']")
    image = avatar.find(".panel-avatar__image", visible: :all)

    page.execute_script("arguments[0].dispatchEvent(new Event('error'))", image)

    expect(avatar["data-image-state"]).to eq("error")
    expect(image).not_to be_visible
    expect(avatar).to have_css(".panel-avatar__fallback", text: "FI")
  end

  it "keeps group rings aligned to the theme background and count size" do
    styles = page.evaluate_script(<<~JS)
      (() => {
        const section = document.getElementById("avatar-preview-heading").closest("section")
        const theme = section.querySelector("[data-theme='panel-dark']")
        const group = theme.querySelector(".panel-avatar-group[data-size='lg']")
        const avatar = group.querySelector(".panel-avatar")
        const count = group.querySelector(".panel-avatar-group__count")
        const avatarStyle = getComputedStyle(avatar)
        const countRect = count.getBoundingClientRect()

        return {
          ring: avatarStyle.boxShadow,
          radius: parseFloat(avatarStyle.borderRadius),
          background: getComputedStyle(theme).getPropertyValue("--background").trim(),
          countSize: [Math.round(countRect.width), Math.round(countRect.height)]
        }
      })()
    JS

    expect(styles.fetch("ring")).not_to eq("none")
    expect(styles.fetch("radius")).to be_positive
    expect(styles.fetch("background")).not_to be_empty
    expect(styles.fetch("countSize")).to eq([ 40, 40 ])
  end

  it "uses a tighter overlap for compact groups than loose groups" do
    spacing = page.evaluate_script(<<~JS)
      (() => {
        const section = document.getElementById("avatar-preview-heading").closest("section")
        const theme = section.querySelector("[data-theme='panel-light']")
        const compact = theme.querySelector(".panel-avatar-group[data-size='default'][data-variant='compact']")
        const loose = theme.querySelector(".panel-avatar-group[data-size='default'][data-variant='loose']")

        return {
          compactMargin: parseFloat(getComputedStyle(compact.children[1]).marginLeft),
          looseMargin: parseFloat(getComputedStyle(loose.children[1]).marginLeft)
        }
      })()
    JS

    expect(spacing.fetch("compactMargin")).to be_negative
    expect(spacing.fetch("looseMargin")).to be_negative
    expect(spacing.fetch("compactMargin")).to be < spacing.fetch("looseMargin")
  end
end
