require "rails_helper"

RSpec.describe "Service spec coverage" do
  it "has a matching spec file for every app/services ruby file" do
    service_files = Dir[Rails.root.join("app/services/**/*.rb")].sort

    missing = service_files.filter_map do |file|
      rel = file.delete_prefix("#{Rails.root}/app/services/").sub(/\.rb\z/, "")
      expected_spec = Rails.root.join("spec/services/#{rel}_spec.rb")
      rel unless File.exist?(expected_spec)
    end

    expect(missing).to eq([]), "Missing spec files for:\n- #{missing.join("\n- ")}"
  end
end
