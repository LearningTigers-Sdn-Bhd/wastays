# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Service spec coverage" do
  it "has a matching spec file for every app/services ruby file" do
    # Services consolidated into e_invoice_services_spec.rb
    consolidated = %w[
      e_invoice/cancel
      e_invoice/phone_formatter
      e_invoice/submission_context
      my_invois/client
      my_invois/client_factory
    ]

    service_files = Dir[Rails.root.join("app/services/**/*.rb")].sort

    missing = service_files.filter_map do |file|
      rel = file.delete_prefix("#{Rails.root}/app/services/").sub(/\.rb\z/, "")
      next if consolidated.include?(rel)
      expected_spec = Rails.root.join("spec/services/#{rel}_spec.rb")
      rel unless File.exist?(expected_spec)
    end

    expect(missing).to eq([]), "Missing spec files for:\n- #{missing.join("\n- ")}"
  end
end
