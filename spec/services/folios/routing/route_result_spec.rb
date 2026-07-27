# frozen_string_literal: true

require "rails_helper"

RSpec.describe Folios::Routing::RouteResult do
  it "carries the target folio and the reason it was chosen" do
    result = described_class.success(folio: "F", route_source: "routing_rule", route_metadata: { folio_routing_rule_id: 7 })

    expect(result).to be_success
    expect(result.folio).to eq("F")
    expect(result.route_source).to eq("routing_rule")
    expect(result.route_metadata).to eq({ folio_routing_rule_id: 7 })
  end

  it "leaves route_source unset when nothing routed the charge" do
    result = described_class.success(folio: "F", route_metadata: {})

    expect(result.route_source).to be_nil
    expect(result.route_metadata).to eq({})
  end

  it "still reports the source it was resolving when it fails" do
    result = described_class.failure("Missing transaction code", route_metadata: {})

    expect(result).not_to be_success
    expect(result.error).to eq("Missing transaction code")
    expect(result.folio).to be_nil
    expect(result.route_metadata).to eq({})
  end
end
