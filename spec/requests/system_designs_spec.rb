# frozen_string_literal: true

require "rails_helper"

RSpec.describe "System design showcase", type: :request do
  it "uses its asset-enabled layout without application chrome" do
    get system_design_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)

    expect(response.body).to include("data-system-design-showcase")
    expect(response.body).to include("stylesheet")
    expect(response.body).to include("importmap")
    expect(document.at_css('body > header, body > nav[aria-label="Global"], body > footer')).to be_nil
    expect(response.body).not_to include("widget.1automations.com")
  end
end
