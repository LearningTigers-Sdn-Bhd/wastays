# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppIconComponent, type: :component do
  before { AppIconComponent::CACHE.clear }

  it "renders the named icon with the given attributes" do
    render_inline(described_class.new("check", class: "size-5", stroke_width: 2.5))

    expect(page).to have_css("svg.size-5[stroke-width='2.5']")
  end

  it "defaults to the configured library and passes through variant/from" do
    render_inline(described_class.new("cigarette", library: "phosphor", variant: "light", class: "size-3"))

    expect(page).to have_css("svg.size-3")
  end

  it "memoizes rendered markup across instances for identical arguments" do
    render_inline(described_class.new("check", class: "size-5"))
    first_size = AppIconComponent::CACHE.size

    render_inline(described_class.new("check", class: "size-5"))

    expect(AppIconComponent::CACHE.size).to eq(first_size)
  end

  it "logs and renders nothing when the icon cannot be found" do
    allow(Rails.logger).to receive(:error)

    render_inline(described_class.new("this-icon-does-not-exist"))

    expect(page.native.inner_html).to be_blank
    expect(Rails.logger).to have_received(:error).with(/Icon not found/)
  end
end
