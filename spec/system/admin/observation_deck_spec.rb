# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Observation Deck", type: :system, js: true do
  let(:account) { create(:account, name: "Observation Deck System") }
  let(:superadmin) { create(:user, :superadmin, account:, email: "observation-deck-system@example.com") }
  let!(:entry) do
    create(
      :observation_entry,
      entry_type: "sql",
      request_id: "observation-deck-system-trace",
      status: 500,
      duration: 1_250,
      path: "Order Load",
      payload: { "sql" => "SELECT * FROM orders" }
    )
  end

  before do
    driven_by(:cuprite)
    sign_in_through_ui(superadmin)
  end

  it "keeps stream and inspector visible on desktop" do
    page.current_window.resize_to(1440, 1000)
    visit admin_observation_deck_index_path

    expect(page).to have_css("#entries_frame")
    expect(page).to have_css("[data-observation-deck-target='desktopInspector']", visible: true)

    find("a[aria-label='Inspect Database: Order Load']").click

    within("#entry_detail_frame") do
      expect(page).to have_content("Database: Order Load")
      expect(page).to have_content("Summary")
      expect(page).to have_content("Trace")
      click_button "Payload"
      expect(page).to have_button("Copy SQL")
    end
  end

  it "opens accessible filter and inspector sheets on mobile" do
    page.current_window.resize_to(390, 844)
    visit admin_observation_deck_index_path

    click_button "More filters"
    expect(page).to have_css("dialog#observation-more-filters[open]")
    find("dialog#observation-more-filters").send_keys(:escape)
    expect(page).to have_no_css("dialog#observation-more-filters[open]")

    event_link = find("a[aria-label='Inspect Database: Order Load']")
    event_link.click
    expect(page).to have_css("dialog#observation-inspector[open]")
    expect(page).to have_css("dialog#observation-inspector #entry_detail_frame")

    within("dialog#observation-inspector") { find("button[aria-label='Close event inspector']").click }
    expect(page).to have_no_css("dialog#observation-inspector[open]")
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  it "persists a selected theme" do
    visit admin_observation_deck_index_path

    find("button[aria-label='Open Observation Deck settings']").click
    find("label", text: "Light").click

    expect(page).to have_css("html[data-observation-deck-theme='light']")
    expect(page.evaluate_script("localStorage.getItem('observation-deck-theme')")).to eq("light")

    visit admin_observation_deck_index_path

    expect(page).to have_css("html[data-observation-deck-theme='light']")
  end

  it "filters events from direct type and status controls" do
    create(:observation_entry, entry_type: "request", status: 500, path: "GET /quick-match")
    create(:observation_entry, entry_type: "sql", status: 500, path: "SELECT excluded")
    create(:observation_entry, entry_type: "request", status: 200, path: "GET /success")

    visit admin_observation_deck_index_path

    click_link "Request"
    expect(page).to have_current_path(/entry_type=request/)
    expect(page).to have_css("a[aria-current='page']", text: "Request")
    expect(page).to have_content("GET /quick-match")
    expect(page).to have_no_content("SELECT excluded")

    click_link "Errors"
    expect(page).to have_current_path(/entry_type=request.*status_group=errors/)
    expect(page).to have_css("a[aria-current='page']", text: "Errors")
    expect(page).to have_content("GET /quick-match")
    expect(page).to have_no_content("GET /success")
  end

  it "labels type and status filter groups" do
    visit admin_observation_deck_index_path

    expect(page).to have_css(".observation-deck__filter-group", count: 2)
    expect(page).to have_css(".observation-deck__filter-group", text: "Event type")
    expect(page).to have_css(".observation-deck__filter-group", text: "Status")
  end

  it "groups filters and health metrics into scanable sections" do
    visit admin_observation_deck_index_path

    expect(page).to have_css(".observation-deck__filter-primary-row .observation-deck__filter-group", count: 2)
    expect(page).to have_css(".observation-deck__filter-actions")
    expect(page).to have_css(".observation-deck__health-metric", count: 4)
  end

  it "spins the refresh icon when refresh starts" do
    visit admin_observation_deck_index_path

    refresh = find("a[aria-label='Refresh event stream']")
    page.execute_script("arguments[0].dispatchEvent(new Event('observation:refresh-test', { bubbles: true }))", refresh)

    expect(refresh["aria-busy"]).to eq("true")
    expect(refresh).to match_css(".is-spinning")
  end

  it "keeps the event stream within a scrollable workspace" do
    create_list(:observation_entry, 60)

    [ 1440, 1110 ].each do |width|
      page.current_window.resize_to(width, 600)
      visit admin_observation_deck_index_path

      dimensions = page.evaluate_script(<<~JS)
        (() => {
          const frame = document.querySelector('#entries_frame')
          const stream = document.querySelector('.observation-deck__table-scroll')
          const styles = getComputedStyle(stream)
          stream.scrollTop = 100
          return {
            frameHeight: frame.clientHeight,
            streamHeight: stream.clientHeight,
            streamContentHeight: stream.scrollHeight,
            scrollPosition: stream.scrollTop,
            scrollbarGutter: styles.scrollbarGutter
          }
        })()
      JS

      expect(dimensions.fetch("frameHeight")).to be_between(1, 600)
      expect(dimensions.fetch("streamHeight")).to be_between(1, 600)
      expect(dimensions.fetch("streamContentHeight")).to be > dimensions.fetch("streamHeight")
      expect(dimensions.fetch("scrollPosition")).to be > 0
      expect(dimensions.fetch("scrollbarGutter")).to include("stable")
    end
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
