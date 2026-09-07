# frozen_string_literal: true

require "rails_helper"

RSpec.describe PanelsUI::Pagination, type: :component do
  def paginate_records(records = (1..55).to_a, params: {}, **options)
    Object.new.extend(Pagy::Method).send(
      :pagy, :offset, records,
      request: { base_url: "http://test.host", path: "/records", params: params.stringify_keys },
      **options
    )
  end

  def render_pagination(pagy, **options)
    render_inline(described_class.new(pagy: pagy, **options))
  end

  it "paginates arrays with explicit request context and server-owned limits" do
    pagy, records = paginate_records(params: { page: "2", limit: "5000" })

    expect(records).to eq((26..50).to_a)
    expect(pagy.limit).to eq(25)
    expect(Pagy::OPTIONS).to be_frozen

    pagy, records = paginate_records(params: { limit: "1" }, limit: 15)
    expect(records).to eq((1..15).to_a)
    expect(pagy.limit).to eq(15)
  end

  it "renders named controls and the current page on desktop and mobile" do
    pagy, = paginate_records(params: { page: "2" })
    render_pagination(pagy, aria_label: "Results pages")

    expect(page).to have_css('nav[aria-label="Results pages"]')
    expect(page).to have_link("First page", href: "/records?page=1", enable_aria_label: true)
    expect(page).to have_link("Previous page", href: "/records?page=1", enable_aria_label: true)
    expect(page).to have_link("Next page", href: "/records?page=3", enable_aria_label: true)
    expect(page).to have_link("Last page", href: "/records?page=3", enable_aria_label: true)
    expect(page).to have_css('[aria-current="page"]', text: "2", count: 2)
    expect(page).to have_css('[data-slot="pagination-mobile"]', text: /Page\s+2\s+of\s+3/)
    expect(page).to have_no_link("Page 2", enable_aria_label: true)
  end

  it "uses Nova pagination structure and button states" do
    pagy, = paginate_records(params: { page: "2" })
    render_pagination(pagy)

    expect(page).to have_css('nav.panel-pagination[data-slot="pagination"]')
    expect(page).to have_css('nav > ul[data-slot="pagination-content"]')
    expect(page).to have_css('ul > li[data-slot="pagination-item"]', minimum: 1)
    expect(page).to have_css('a[data-slot="pagination-link"][data-state="available"][data-variant="ghost"][data-size="icon"][data-icon-only="true"]')
    expect(page).to have_css('span.panel-pagination__current[data-state="current"][data-variant="neutral"][data-size="icon"][data-icon-only="true"]', count: 2)
  end

  it "disables boundary controls without links" do
    pagy, = paginate_records
    render_pagination(pagy)
    expect(page).to have_css('span[aria-label="First page"][aria-disabled="true"][data-state="disabled"]')
    expect(page).to have_css('span[aria-label="Previous page"][aria-disabled="true"][data-state="disabled"]')
    expect(page).to have_no_link("First page", enable_aria_label: true)

    pagy, = paginate_records(params: { page: "3" })
    render_pagination(pagy)
    expect(page).to have_css('span[aria-label="Last page"][aria-disabled="true"][data-state="disabled"]')
    expect(page).to have_css('span[aria-label="Next page"][aria-disabled="true"][data-state="disabled"]')
    expect(page).to have_no_link("Next page", enable_aria_label: true)
  end

  it "renders gaps for large collections using the installed Pagy series helper" do
    pagy, = paginate_records((1..1000).to_a, params: { page: "20" })
    render_pagination(pagy)

    expect(page).to have_css('[data-slot="pagination-ellipsis"][aria-hidden="true"]', count: 2)
    expect(page).to have_link("Page 1", enable_aria_label: true)
    expect(page).to have_link("Page 40", enable_aria_label: true)
  end

  [ [], [ 1 ] ].each do |records|
    it "renders one disabled page for #{records.empty? ? 'empty' : 'single-page'} results, or hides it on request" do
      pagy, = paginate_records(records)
      render_pagination(pagy)

      expect(page).to have_css('[aria-current="page"]', text: "1", count: 1)
      expect(page).to have_css('[aria-disabled="true"]', count: 2)
      expect(page).to have_no_css("a")

      render_pagination(pagy, hide_when_single_page: true)
      expect(page).to have_no_css("nav")
    end
  end

  it "returns an empty array on overflow and offers a link back to the last page" do
    pagy, records = paginate_records(params: { page: "99" })
    expect(records).to eq([])
    render_pagination(pagy)

    expect(page).to have_link("Previous page", href: "/records?page=3", enable_aria_label: true)
    expect(page).to have_no_link("Next page", enable_aria_label: true)
  end

  it "preserves filters and independent page keys without mutating request parameters" do
    params = { "arrival_page" => "2", "checkout_page" => "3", "query" => "Jane & John", "tab" => "arrivals" }.freeze
    arrivals, = paginate_records(params: params, page_key: "arrival_page")
    checkout, = paginate_records(params: params, page_key: "checkout_page")

    [ [ arrivals, "arrival_page", "checkout_page", "3" ], [ checkout, "checkout_page", "arrival_page", "2" ] ].each do |pagy, own_key, other_key, other_page|
      render_pagination(pagy)
      label = pagy.page == 2 ? "Next page" : "Page 2"
      href = page.find_link(label, enable_aria_label: true)[:href]
      query = Rack::Utils.parse_nested_query(URI.parse(href).query)
      expect(query).to include("query" => "Jane & John", "tab" => "arrivals", other_key => other_page)
      expect(query[own_key]).not_to eq(params[own_key])
    end
    expect(params).to include("arrival_page" => "2", "checkout_page" => "3")
  end

  it "escapes URL attributes and applies Turbo data only when supplied" do
    query = '\"><script>alert(1)</script>'
    pagy, = paginate_records(params: { query: query })
    render_pagination(pagy)
    expect(page).to have_no_css("[data-turbo-action], [data-turbo-frame]")

    render_pagination(pagy, link_data: { turbo_frame: "results", turbo_action: "advance" })
    expect(page).to have_no_css("script")
    page.all("a").each do |link|
      expect(link["data-turbo-frame"]).to eq("results")
      expect(link["data-turbo-action"]).to eq("advance")
      expect(Rack::Utils.parse_nested_query(URI.parse(link[:href]).query)["query"]).to eq(query)
    end
  end
end
