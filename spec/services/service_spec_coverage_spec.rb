require "rails_helper"

RSpec.describe "Service spec coverage" do
  GROUPED_SERVICE_SPECS = {
    "e_invoice/cancel" => "e_invoice_services_spec.rb",
    "e_invoice/phone_formatter" => "e_invoice_services_spec.rb",
    "e_invoice/submission_context" => "e_invoice_services_spec.rb",
    "my_invois/client" => "e_invoice_services_spec.rb",
    "my_invois/client_factory" => "e_invoice_services_spec.rb",
    "onboarding/approve_onboarding" => "onboarding/review_lifecycle_spec.rb",
    "onboarding/commercial_rows" => "onboarding/commercial_setup_spec.rb",
    "onboarding/complete_training" => "onboarding/review_lifecycle_spec.rb",
    "onboarding/confirm_role_presets" => "onboarding/property_and_team_spec.rb",
    "onboarding/create_deliveries" => "onboarding/review_lifecycle_spec.rb",
    "onboarding/decide_no_additional_staff" => "onboarding/property_and_team_spec.rb",
    "onboarding/decide_no_corporate_accounts" => "onboarding/commercial_setup_spec.rb",
    "onboarding/deliver_invitation_draft" => "onboarding/deliver_invitations_spec.rb",
    "onboarding/initialize_progress" => "onboarding/foundation_spec.rb",
    "onboarding/invalidate_dependent_sections" => "onboarding/rooms_spec.rb",
    "onboarding/invalidate_room_revenue" => "onboarding/taxes_and_room_revenue_spec.rb",
    "onboarding/navigation_state" => "onboarding/foundation_spec.rb",
    "onboarding/readiness" => "onboarding/foundation_spec.rb",
    "onboarding/request_changes" => "onboarding/review_lifecycle_spec.rb",
    "onboarding/resume_page_resolver" => "onboarding/foundation_spec.rb",
    "onboarding/save_corporate_drafts" => "onboarding/commercial_setup_spec.rb",
    "onboarding/save_discounts" => "onboarding/commercial_setup_spec.rb",
    "onboarding/save_extra_charges" => "onboarding/commercial_setup_spec.rb",
    "onboarding/save_ota_credentials" => "onboarding/commercial_setup_spec.rb",
    "onboarding/save_payment_methods" => "onboarding/commercial_setup_spec.rb",
    "onboarding/save_property_photos" => "onboarding/property_and_team_spec.rb",
    "onboarding/save_property_profile" => "onboarding/property_and_team_spec.rb",
    "onboarding/save_rates_availability" => "onboarding/rates_availability_spec.rb",
    "onboarding/save_room_revenue" => "onboarding/taxes_and_room_revenue_spec.rb",
    "onboarding/save_rooms" => "onboarding/rooms_spec.rb",
    "onboarding/save_staff_drafts" => "onboarding/property_and_team_spec.rb",
    "onboarding/save_taxes_fees" => "onboarding/taxes_and_room_revenue_spec.rb",
    "onboarding/section_catalog" => "onboarding/foundation_spec.rb",
    "onboarding/skip_optional_section" => "onboarding/commercial_setup_spec.rb",
    "onboarding/submit_onboarding" => "onboarding/review_lifecycle_spec.rb",
    "onboarding/tax_fingerprint" => "onboarding/taxes_and_room_revenue_spec.rb",
    "onboarding/transition_lifecycle" => "onboarding/foundation_spec.rb",
    "onboarding/update_section" => "onboarding/foundation_spec.rb"
  }.freeze

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

  def grouped_spec_exists?(path)
    grouped_spec = GROUPED_SERVICE_SPECS[path]
    grouped_spec.present? && Rails.root.join("spec/services", grouped_spec).exist?
  end

  it "has a matching or explicitly grouped spec for every non-export app/services ruby file" do
    service_files = Dir[Rails.root.join("app/services/**/*.rb")].sort

    missing = service_files.filter_map do |file|
      rel = file.delete_prefix("#{Rails.root}/app/services/").sub(/\.rb\z/, "")
      expected_spec = Rails.root.join("spec/services/#{rel}_spec.rb")
      rel unless report_export_infrastructure?(rel) || File.exist?(expected_spec) || grouped_spec_exists?(rel)
    end

    expect(missing).to eq([]), "Missing spec files for:\n- #{missing.join("\n- ")}"
  end

  it "exempts only report export infrastructure from one-file-per-spec enforcement" do
    expect(report_export_infrastructure?("hotel_portal/reports/police_report_csv_export_service")).to be(true)
    expect(report_export_infrastructure?("hotel_portal/reports/police_report_export_table")).to be(true)
    expect(report_export_infrastructure?("hotel_portal/reports/police_report")).to be(false)
  end

  it "keeps grouped service spec declarations valid" do
    invalid = GROUPED_SERVICE_SPECS.filter_map do |service, grouped_spec|
      service_file = Rails.root.join("app/services/#{service}.rb")
      spec_file = Rails.root.join("spec/services", grouped_spec)
      service unless service_file.exist? && spec_file.exist?
    end

    expect(invalid).to eq([]), "Invalid grouped service spec declarations:\n- #{invalid.join("\n- ")}"
  end
end
