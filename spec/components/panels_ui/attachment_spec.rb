# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Attachment, type: :component do
  it "renders file metadata, media, actions, state, and percentage text" do
    render_inline(
      described_class.new(
        title: "folio.pdf",
        state: :uploading,
        size: :sm,
        progress: 42
      )
    ) do |attachment|
      attachment.with_media(variant: :icon) { "PDF" }
      attachment.with_actions { "Remove" }
    end

    root = page.find(".panel-attachment")
    expect(root["data-state"]).to eq("uploading")
    expect(root["data-size"]).to eq("sm")
    expect(root["data-orientation"]).to eq("horizontal")
    expect(page).to have_css(".panel-attachment__media[data-variant='icon']", text: "PDF")
    expect(page).to have_css(".panel-attachment__title", text: "folio.pdf")
    expect(page).to have_css(".panel-attachment__description", text: "Uploading · 42%")
    expect(page).to have_no_css("progress.panel-progress")
    expect(page).to have_css(".panel-attachment__actions", text: "Remove")
  end

  it "falls back invalid variants and renders a default file icon" do
    render_inline(described_class.new(title: "notes.txt", state: :unknown, size: :huge, orientation: :diagonal))

    expect(page).to have_css(".panel-attachment[data-state='ready'][data-size='default'][data-orientation='horizontal']")
    expect(page).to have_css(".panel-attachment__media[data-variant='icon'] svg")
    expect(page).to have_css(".panel-attachment__description", text: "Ready to upload")
  end

  it "supports ready and uploaded states with idle and done compatibility aliases" do
    render_inline(described_class.new(title: "selected.pdf", state: :idle))
    expect(page).to have_css(".panel-attachment[data-state='ready']")

    render_inline(described_class.new(title: "uploaded.pdf", state: :done))
    expect(page).to have_css(".panel-attachment[data-state='uploaded']")
    expect(page).to have_css(".panel-attachment__description", text: "Uploaded")
  end

  it "renders a full-card link trigger independently from actions" do
    render_inline(described_class.new(title: "report.pdf")) do |attachment|
      attachment.with_trigger(href: "/report.pdf", aria_label: "Open report.pdf", target: "_blank")
      attachment.with_actions { "Remove" }
    end

    expect(page).to have_css(".panel-attachment[data-interactive='true']")
    expect(page).to have_css("a.panel-attachment__trigger[href='/report.pdf'][aria-label='Open report.pdf'][data-slot='attachment-trigger']")
    expect(page).to have_css(".panel-attachment__actions", text: "Remove")
  end

  it "renders a native button trigger for dialog commands" do
    render_inline(described_class.new(title: "photo.jpg")) do |attachment|
      attachment.with_trigger(
        aria_label: "Preview photo.jpg",
        command: "show-modal",
        commandfor: "photo-preview"
      )
    end

    expect(page).to have_css("button.panel-attachment__trigger[type='button'][command='show-modal'][commandfor='photo-preview']")
  end

  it "requires an accessible trigger label" do
    expect do
      render_inline(described_class.new(title: "report.pdf")) do |attachment|
        attachment.with_trigger(href: "/report.pdf")
      end
    end.to raise_error(ArgumentError, "Attachment triggers require an aria_label or aria: { label: ... }")
  end

  it "rejects non-numeric progress" do
    expect do
      render_inline(described_class.new(title: "notes.txt", progress: "later"))
    end.to raise_error(ArgumentError, "progress must be numeric")
  end
end
