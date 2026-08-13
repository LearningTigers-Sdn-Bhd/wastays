# frozen_string_literal: true

require "rails_helper"

direct_invocation = RSpec.configuration.files_to_run.one? &&
  File.expand_path(RSpec.configuration.files_to_run.first) == File.expand_path(__FILE__)

# Defining no examples when a domain/directory includes this file keeps live
# writes completely outside the default channel suite, even when a developer
# happens to have a staging key in their shell.
RSpec.describe "Channex staging rate plan and ARI contract", :channex_staging do
  let(:api_key) { ENV["CHANNEX_STAGING_API_KEY"] }
  let(:client) { Channex::Client.new(api_key: api_key, environment: "staging") }

  around do |example|
    skip "Run this spec directly with CHANNEX_STAGING_API_KEY set" unless api_key.present?

    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  it "round-trips per-room and multi-occupancy plans and ARI without warnings" do
    suffix = "wastays-contract-#{Time.current.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(4)}"
    created = {}
    date = Date.current + 30.days

    property = post_without_warnings("/properties", property: {
      title: suffix,
      city: "Kuala Lumpur",
      country: "MY",
      currency: "MYR",
      timezone: "Asia/Kuala_Lumpur"
    })
    created[:property] = data_id(property)

    room = post_without_warnings("/room_types", room_type: {
      property_id: created[:property],
      title: "Contract Room #{suffix}",
      count_of_rooms: 1,
      occ_adults: 3,
      occ_children: 2,
      occ_infants: 1,
      default_occupancy: 2
    })
    created[:room_type] = data_id(room)

    per_room = post_without_warnings("/rate_plans", rate_plan: {
      property_id: created[:property],
      room_type_id: created[:room_type],
      title: "Contract Room Rate #{suffix}",
      currency: "MYR",
      sell_mode: "per_room",
      rate_mode: "manual",
      options: [ { occupancy: 3, is_primary: true, rate: "199.95" } ]
    })
    created[:per_room_plan] = data_id(per_room)

    per_person = post_without_warnings("/rate_plans", rate_plan: {
      property_id: created[:property],
      room_type_id: created[:room_type],
      title: "Contract Occupancy Rate #{suffix}",
      currency: "MYR",
      sell_mode: "per_person",
      rate_mode: "manual",
      children_fee: "25.50",
      infant_fee: "0.00",
      options: [
        { occupancy: 1, is_primary: false, rate: "100.11" },
        { occupancy: 2, is_primary: true, rate: "150.22" },
        { occupancy: 3, is_primary: false, rate: "200.33" }
      ]
    })
    created[:per_person_plan] = data_id(per_person)

    per_room_read = client.get("/rate_plans/#{created[:per_room_plan]}")
    per_person_read = client.get("/rate_plans/#{created[:per_person_plan]}")
    expect(warnings(per_room_read)).to be_empty
    expect(warnings(per_person_read)).to be_empty
    expect(attributes(per_room_read)["options"]).to contain_exactly(hash_including("occupancy" => 3, "is_primary" => true))
    expect(attributes(per_person_read)).to include("children_fee" => "25.50", "infant_fee" => "0.00")
    expect(attributes(per_person_read)["options"]).to contain_exactly(
      hash_including("occupancy" => 1, "is_primary" => false),
      hash_including("occupancy" => 2, "is_primary" => true),
      hash_including("occupancy" => 3, "is_primary" => false)
    )

    ari = post_without_warnings("/restrictions", values: [
      {
        property_id: created[:property], rate_plan_id: created[:per_room_plan],
        date_from: date.to_s, date_to: date.to_s, rate: "199.95", max_stay: 9
      },
      {
        property_id: created[:property], rate_plan_id: created[:per_person_plan],
        date_from: date.to_s, date_to: date.to_s,
        rate: [ [ 1, "100.11" ], [ 2, "150.22" ], [ 3, "200.33" ] ], max_stay: 9
      }
    ])
    expect(task_ids(ari)).to all(be_present)

    readback = wait_for_ari_readback(created.values_at(:per_room_plan, :per_person_plan), property_id: created[:property], date: date)
    expect(readback[:error] || readback["error"]).to be_nil
    expect(warnings(readback)).to be_empty
    values = readback["data"].is_a?(Array) ? readback["data"] : readback.dig("data", "values")
    expect(values).to include(
      hash_including("rate_plan_id" => created[:per_room_plan], "rate" => "199.95", "max_stay" => 9),
      hash_including("rate_plan_id" => created[:per_person_plan], "rate" => [ [ 1, "100.11" ], [ 2, "150.22" ], [ 3, "200.33" ] ], "max_stay" => 9)
    )
  ensure
    client.delete("/rate_plans/#{created[:per_person_plan]}") if created&.dig(:per_person_plan)
    client.delete("/rate_plans/#{created[:per_room_plan]}") if created&.dig(:per_room_plan)
    client.delete("/room_types/#{created[:room_type]}") if created&.dig(:room_type)
    client.delete("/properties/#{created[:property]}") if created&.dig(:property)
  end

  def post_without_warnings(path, payload)
    response = client.post(path, payload)
    expect(response[:error] || response["error"]).to be_nil
    expect(warnings(response)).to be_empty
    response
  end

  def warnings(response)
    response.dig("meta", "warnings").to_a
  end

  def data_id(response)
    data = response.fetch("data")
    data.is_a?(Array) ? data.first.fetch("id") : data.fetch("id")
  end

  def attributes(response)
    data = response.fetch("data")
    data.fetch("attributes", data)
  end

  def task_ids(response)
    data = response.fetch("data")
    Array.wrap(data).map { |item| item.fetch("id") }
  end

  def wait_for_ari_readback(rate_plan_ids, property_id:, date:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 20
    loop do
      response = client.get("/restrictions", property_id: property_id, date_from: date.to_s, date_to: date.to_s)
      values = response["data"].is_a?(Array) ? response["data"] : response.dig("data", "values")
      returned_ids = Array(values).map { |value| value["rate_plan_id"] }
      return response if rate_plan_ids.all? { |id| returned_ids.include?(id) }
      return response if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 1
    end
  end
end if direct_invocation
