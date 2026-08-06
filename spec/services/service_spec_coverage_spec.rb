require "rails_helper"

RSpec.describe "Service spec coverage" do
  REPORT_EXPORT_INFRASTRUCTURE = [
    %r{\Ahotel_portal/reports/exports/},
    %r{\Ahotel_portal/reports/.+_(?:csv|excel|pdf)_export_service\z},
    %r{\Ahotel_portal/reports/.+_export_(?:table|result)\z},
    %r{\Ahotel_portal/reports/excel_export_styles\z},
    %r{\Areports/housekeeping_tasks_(?:csv|excel)_generator\z},
    %r{\Areports/housekeeping_tasks_export_table\z}
  ].freeze

  def report_export_infrastructure?(path)
    REPORT_EXPORT_INFRASTRUCTURE.any? { |pattern| path.match?(pattern) }
  end

  it "has a matching spec file for every non-export app/services ruby file" do
    service_files = Dir[Rails.root.join("app/services/**/*.rb")].sort

    missing = service_files.filter_map do |file|
      rel = file.delete_prefix("#{Rails.root}/app/services/").sub(/\.rb\z/, "")
      expected_spec = Rails.root.join("spec/services/#{rel}_spec.rb")
      rel unless report_export_infrastructure?(rel) || File.exist?(expected_spec)
    end

    expect(missing).to eq([]), "Missing spec files for:\n- #{missing.join("\n- ")}"
  end

  it "exempts only report export infrastructure from one-file-per-spec enforcement" do
    expect(report_export_infrastructure?("hotel_portal/reports/police_report_csv_export_service")).to be(true)
    expect(report_export_infrastructure?("hotel_portal/reports/police_report_export_table")).to be(true)
    expect(report_export_infrastructure?("hotel_portal/reports/police_report")).to be(false)
  end
end
