# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PanelsUI::Card", type: :system do
  before { visit "/system-design" }

  it "activates the primary link with the keyboard" do
    link = find("[data-testid='clickable-record-card'] .panel-card__primary-link")
    # The system-design page runs a scrollspy that owns location.hash, so assert
    # the keyboard activation directly (the accessibility intent) rather than the
    # transient URL, which the scrollspy resets to the visible section on scroll.
    page.execute_script(<<~JS, link)
      const link = arguments[0]
      window.__cardLinkActivatedHref = null
      link.addEventListener("click", (event) => {
        event.preventDefault()
        window.__cardLinkActivatedHref = event.currentTarget.getAttribute("href")
      }, { once: true })
      link.focus()
    JS
    link.send_keys(:enter)

    expect(page.evaluate_script("window.__cardLinkActivatedHref")).to eq("#card-booking-1042")
  end

  it "keeps a nested action independent from card navigation" do
    find("#card-secondary-action").click

    expect(page).to have_current_path("/system-design")
    expect(page).to have_css("[data-testid='clickable-record-card']", text: "Booking #1042")
  end

  it "stretches the primary link over the non-interactive card surface" do
    covering_element = page.evaluate_script(<<~JS)
      (() => {
        const content = document.querySelector("[data-testid='clickable-record-card'] .panel-card__content")
        content.scrollIntoView({ block: "center" })
        const rect = content.getBoundingClientRect()
        const element = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2)
        return element.className
      })()
    JS

    expect(covering_element).to include("panel-card__primary-link")
  end

  it "uses the active theme tokens for card text and surfaces" do
    mismatches = page.evaluate_script(<<~JS)
      (() => {
      const parseOklch = (value) => {
        const match = value.match(/oklch\\(([-.\\d]+%?)\\s+([-.\\d]+)\\s+([-.\\d]+)/)
        if (!match) return null
        const lightness = match[1].endsWith("%") ? parseFloat(match[1]) / 100 : parseFloat(match[1])
        return [lightness, parseFloat(match[2]), parseFloat(match[3])]
      }
      const sameColor = (actual, expected) => {
        const left = parseOklch(actual)
        const right = parseOklch(expected)
        return left && right && left.every((channel, index) => Math.abs(channel - right[index]) < 0.0001)
      }

      return [...document.querySelectorAll("#card-preview-heading ~ * .panel-card")].flatMap((card) => {
        const styles = getComputedStyle(card)
        const expectedSurface = styles.getPropertyValue("--card").trim()
        const expectedMuted = styles.getPropertyValue("--muted-foreground").trim()
        const issues = []

        if (!sameColor(styles.backgroundColor, expectedSurface) && card.dataset.mediaPosition !== "background") {
          issues.push(`surface:${styles.backgroundColor}:${expectedSurface}`)
        }

        if (card.dataset.mediaPosition !== "background") {
          card.querySelectorAll(".panel-card__description, .panel-card__content .text-muted-foreground").forEach((text) => {
            const actual = getComputedStyle(text).color
            if (!sameColor(actual, expectedMuted)) issues.push(`muted:${actual}:${expectedMuted}`)
          })
        }

        return issues
      })
      })()
    JS

    expect(mismatches).to be_empty
  end

  it "renders labelled preview actions" do
    expect(page).to have_button("Edit")
    expect(page).to have_button("Open reservation")
    expect(page).to have_button("View room")
  end

  it "keeps title and description spacing independent from header actions" do
    spacing = page.evaluate_script(<<~JS)
      (() => {
        const card = [...document.querySelectorAll(".panel-card")]
          .find((candidate) => candidate.textContent.includes("Complete reservation panel"))
        const title = card.querySelector(".panel-card__title").getBoundingClientRect()
        const description = card.querySelector(".panel-card__description").getBoundingClientRect()
        return description.top - title.bottom
      })()
    JS

    expect(spacing).to be_within(0.5).of(4)
  end

  it "keeps horizontal media clipped and anchors the footer to the card bottom" do
    geometry = page.evaluate_script(<<~JS)
      (() => {
        const card = [...document.querySelectorAll(".panel-card[data-orientation='horizontal']")]
          .find((candidate) => candidate.querySelector(".panel-card__footer"))
        const media = card.querySelector(".panel-card__media[data-position='leading']")
        const footer = card.querySelector(".panel-card__footer")
        const cardRect = card.getBoundingClientRect()
        const mediaRect = media.getBoundingClientRect()
        const footerRect = footer.getBoundingClientRect()
        const cardStyles = getComputedStyle(card)
        const mediaStyles = getComputedStyle(media)

        return {
          cardHeight: cardRect.height,
          mediaHeight: mediaRect.height,
          footerGap: Math.abs(cardRect.bottom - footerRect.bottom),
          overflow: mediaStyles.overflow,
          cardRadius: cardStyles.borderTopLeftRadius,
          mediaRadius: mediaStyles.borderTopLeftRadius,
          footerBottomLeftRadius: getComputedStyle(footer).borderBottomLeftRadius,
          footerBottomRightRadius: getComputedStyle(footer).borderBottomRightRadius
        }
      })()
    JS

    expect(geometry.fetch("cardHeight")).to be < 500
    expect(geometry.fetch("mediaHeight")).to be_within(2).of(geometry.fetch("cardHeight"))
    expect(geometry.fetch("footerGap")).to be <= 2
    expect(geometry.fetch("overflow")).to eq("hidden")
    expect(geometry.fetch("mediaRadius")).to eq(geometry.fetch("cardRadius"))
    expect(geometry.fetch("footerBottomLeftRadius")).to eq("0px")
    expect(geometry.fetch("footerBottomRightRadius")).to eq(geometry.fetch("cardRadius"))
  end

  it "frames both density theme previews with visible card surfaces" do
    %w[panel-light panel-dark].each do |theme|
      expect(page).to have_css(
        "[data-theme='#{theme}'].rounded-2xl.border.border-border.bg-card.shadow-sm",
        text: theme == "panel-light" ? "Light densities" : "Dark densities"
      )
    end
  end

  it "places the narrow body and stats cards together at the top" do
    row = page.find("[data-testid='card-simple-patterns']")

    expect(row).to have_css(":scope > .panel-card", count: 2)
    expect(row).to have_text("Narrow body-only card")
    expect(row).to have_text("Occupancy")
  end
end
