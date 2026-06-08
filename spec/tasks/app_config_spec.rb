# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "app_config:encrypt_existing" do
  before(:all) do
    Rails.application.load_tasks
  end

  before do
    Rake::Task["app_config:encrypt_existing"].reenable
  end

  it "encrypts plaintext app config values without reading them through the encrypted attribute first" do
    AppConfig.connection.execute(
      AppConfig.sanitize_sql_array([
        "INSERT INTO app_configs (key, value, created_at, updated_at) VALUES (?, ?, ?, ?)",
        "webhook_url",
        "https://hooks.demo.wastays.com/booking-events",
        Time.current,
        Time.current
      ])
    )

    expect { Rake::Task["app_config:encrypt_existing"].invoke }
      .not_to raise_error

    config = AppConfig.find_by!(key: "webhook_url")
    raw_value = config.read_attribute_before_type_cast(:value)

    expect(config.value).to eq("https://hooks.demo.wastays.com/booking-events")
    expect(raw_value).to include('"p"')
    expect(raw_value).not_to include("https://hooks.demo.wastays.com/booking-events")
  end
end
