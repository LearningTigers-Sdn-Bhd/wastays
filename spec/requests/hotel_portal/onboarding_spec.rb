# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Hotel onboarding shell", type: :request do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "setup") }
  let(:user) { create(:user, account: account) }
  let(:role) { create(:role, account: account) }
  let(:property_params) do
    {
      name: hotel.name,
      address: "12 Beach Road",
      city: "Kuala Lumpur",
      country: "Malaysia",
      time_zone: "Kuala Lumpur",
      default_currency: "MYR",
      contact_email: "stay@example.com",
      contact_phone: "+60312345678"
    }
  end

  before do
    permission = Permission.find_or_create_by!(slug: "manage_hotel_profile") { |record| record.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: permission)
    create(:user_hotel_access, user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  it "resolves the onboarding root to the first incomplete section" do
    get hotel_onboarding_path(hotel)

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.count).to eq(14)
  end

  it "renders the dedicated shell with accessible phase navigation" do
    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Onboarding progress")
    document = response.parsed_body
    expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Property profile" ])
    expect(document.at_css("nav[aria-label='Property steps']")).to be_present
    expect(document.at_css("section[aria-label='Identity and guest details']")).to be_present
    expect(document.css("h2").map { |heading| heading.text.strip }).not_to include("Identity and guest details")
    expect(response.body).not_to include("The legal account was created by WAStays")
    expect(response.body).to include("Save draft")
    expect(response.body).not_to include("Open navigation")
  end

  it "keeps the section actions in the shell footer, outside the scrolling body" do
    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    document = Nokogiri::HTML(response.body)
    footer = document.at_css("footer[data-slot='setup-actions']")

    expect(footer.text).to include("Save draft", "Save & continue")
    expect(document.at_css("div.overflow-y-auto footer[data-slot='setup-actions']")).to be_nil
    expect(document.at_css("div.overflow-y-auto").text).not_to include("Save draft")
  end

  it "redirects a locked deep link to the earliest unmet prerequisite" do
    get hotel_onboarding_section_path(hotel, section_key: "taxes_fees")

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    follow_redirect!
    expect(response.body).to include("Complete the earlier onboarding steps")
  end

  it "saves a draft without completing the section" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft", hotel: property_params }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_profile"))
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("in_progress")
  end

  # The value has to clear three separate permit lists on this path — the save
  # service, the profile form it delegates to, and the controller's re-render list
  # — so it is worth asserting it actually lands.
  it "stores normalized business registration numbers without gating completion" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft", hotel: property_params.merge(tin: " c1234567890 ", ssm_number: "202301012345") }

    expect(hotel.reload.tin).to eq("C1234567890")
    expect(hotel.ssm_number).to eq("202301012345")
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("in_progress")
  end

  it "requires the property completion contract before advancing" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: {
            navigation_action: "save_continue",
            hotel: property_params.except(:contact_email),
            property_policy: { check_in_time: "15:00", check_out_time: "11:00" }
          }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Contact email")
    expect(hotel.onboarding_sections.find_by!(section_key: "property_profile").state).to eq("not_started")
  end

  it "saves a complete property profile and advances without placeholder metadata" do
    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: {
            navigation_action: "save_continue",
            hotel: property_params,
            property_policy: { check_in_time: "15:00", check_out_time: "11:00" }
          }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "property_photos"))
    section = hotel.onboarding_sections.find_by!(section_key: "property_profile")
    expect(section).to have_attributes(state: "complete", decision_metadata: include("source" => "property_profile"))
    expect(section.decision_metadata).not_to have_key("placeholder")
  end

  describe "the property photos step" do
    before { hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete") }

    # Both real upload paths — the profile form and the onboarding upload queue —
    # attach through this method, which is where a first photo becomes featured.
    def attach_photo(filename = "property.jpg")
      blob = ActiveStorage::Blob.create_and_upload!(
        io: File.open(Rails.root.join("spec/fixtures/files/sample_image.jpg")),
        filename: filename,
        content_type: "image/jpeg"
      )
      hotel.attach_photos_with_limit([ blob ])
    end

    it "opens on an empty state that carries the upload action alone" do
      get hotel_onboarding_section_path(hotel, section_key: "property_photos")

      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Property photos" ])
      expect(document.at_css(".panel-empty-state__title").text.squish).to eq("No photos yet")
      # The step heading is the shell's, and the empty state owns the only
      # upload button on the page while the album is empty.
      expect(document.css("h2").map { |heading| heading.text.strip }).not_to include("Property photos")
      expect(document.css("button[commandfor='hotel-photo-upload-sheet']").size).to eq(1)
    end

    it "will not advance until the property has a photo" do
      patch hotel_onboarding_section_path(hotel, section_key: "property_photos"),
            params: { navigation_action: "save_continue" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Upload at least one photo")
      expect(hotel.onboarding_sections.find_by!(section_key: "property_photos").state).to eq("not_started")
    end

    # The owner is never asked to nominate a featured photo, so one photo has to
    # be enough on its own to satisfy the step.
    it "advances on a single photo, which features itself" do
      attach_photo

      patch hotel_onboarding_section_path(hotel, section_key: "property_photos"),
            params: { navigation_action: "save_continue" }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "roles_permissions"))
      expect(hotel.reload.featured_photo_attachment_id).to eq(hotel.photos.attachments.sole.id)
      expect(hotel.onboarding_sections.find_by!(section_key: "property_photos"))
        .to have_attributes(state: "complete", decision_metadata: include("source" => "property_photos"))
    end

    it "keeps a featured photo when the featured one is removed" do
      attach_photo("first.jpg")
      attach_photo("second.jpg")
      first, second = hotel.photos.attachments.order(:id).to_a
      expect(hotel.reload.featured_photo_attachment_id).to eq(first.id)

      delete hotel_profile_photo_path(hotel, first.id, return_to: "onboarding")

      expect(hotel.reload.featured_photo_attachment_id).to eq(second.id)
      expect(hotel).to be_property_photos_ready
    end

    it "leaves no featured photo once the last one is removed" do
      attach_photo
      photo = hotel.photos.attachments.sole

      delete hotel_profile_photo_path(hotel, photo.id, return_to: "onboarding")

      expect(hotel.reload.featured_photo_attachment_id).to be_nil
      expect(hotel).not_to be_property_photos_ready
    end
  end

  it "shows and confirms the four seeded role presets regardless of plan feature access" do
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "property_photos", state: "complete")

    get hotel_onboarding_section_path(hotel, section_key: "roles_permissions")
    expect(response).to have_http_status(:ok)
    presets_page = response.parsed_body
    expect(presets_page.css("h1").map { |heading| heading.text.strip }).to eq([ "Roles and permissions" ])
    expect(presets_page.at_css("section[aria-label='Seeded role presets']")).to be_present
    expect(presets_page.css("h2").map { |heading| heading.text.strip }).not_to include("Seeded role presets")

    patch hotel_onboarding_section_path(hotel, section_key: "roles_permissions"),
          params: { navigation_action: "save_continue", confirm_presets: "1" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "staff_setup"))
    follow_redirect!
    expect(response.body).to include("Add staff member", "No staff added yet")
    staff_page = response.parsed_body
    expect(staff_page.css("h1").map { |heading| heading.text.strip }).to eq([ "Staff setup" ])
    expect(staff_page.at_css("section[aria-label='Draft staff']")).to be_present
    expect(staff_page.css("h2").map { |heading| heading.text.strip }).not_to include("Draft staff")
    expect(account.roles.where(slug: Onboarding::ConfirmRolePresets::PRESET_SLUGS).count).to eq(4)
    expect(hotel.onboarding_sections.find_by!(section_key: "roles_permissions").decision_metadata)
      .to include("permission_fingerprint" => be_present)
  end

  it "stores staff drafts without sending invitations" do
    HotelOps::SeedAccountRoles.call(account)
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")
    staff_role = account.roles.find_by!(slug: "front_desk")

    invitation_count = StaffInvitation.count
    delivery_count = ActionMailer::Base.deliveries.count
    expect {
      patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
            params: {
              navigation_action: "save_continue",
              staff_entries: { "0" => { name: "Ari", email: "ARI@example.com", role_id: staff_role.id } }
            }
    }.to change(OnboardingStaffDraft, :count).by(1)

    expect(StaffInvitation.count).to eq(invitation_count)
    expect(ActionMailer::Base.deliveries.count).to eq(delivery_count)
    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_staff_drafts.first).to have_attributes(email: "ari@example.com", role: staff_role)
  end

  # An emptied table is the decision. Continuing from one records it and discards
  # the drafts, so nobody the owner just removed is left queued for an invitation.
  it "reads an empty staff table as the no-additional-staff decision and clears drafts" do
    HotelOps::SeedAccountRoles.call(account)
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")
    create(:onboarding_staff_draft, hotel: hotel, role: account.roles.find_by!(slug: "housekeeper"))

    patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
          params: { navigation_action: "save_continue", staff_entries: {} }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    expect(hotel.onboarding_staff_drafts).to be_empty
    expect(hotel.onboarding_sections.find_by!(section_key: "staff_setup")).to have_attributes(
      state: "skipped",
      decision_metadata: include("decision" => "no_additional_staff")
    )
  end

  it "offers no separate staff skip button and rejects a forged one" do
    HotelOps::SeedAccountRoles.call(account)
    hotel.onboarding_sections.create!(section_key: "property_profile", state: "complete")
    hotel.onboarding_sections.create!(section_key: "roles_permissions", state: "complete")

    get hotel_onboarding_section_path(hotel, section_key: "staff_setup")
    expect(response.body).not_to include("navigation_action\" value=\"skip\"")

    patch hotel_onboarding_section_path(hotel, section_key: "staff_setup"),
          params: { navigation_action: "skip" }

    expect(response).to have_http_status(:unprocessable_content)
    expect(hotel.onboarding_sections.find_by!(section_key: "staff_setup").state).not_to eq("skipped")
  end

  it "keeps pending-review onboarding read-only" do
    hotel.update!(status: "pending_review")

    patch hotel_onboarding_section_path(hotel, section_key: "property_profile"),
          params: { navigation_action: "save_draft" }

    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "review"))
    expect(hotel.onboarding_sections).to be_empty

    follow_redirect!
    expect(response.body).to include("Awaiting WAStays review")
    expect(response.body).not_to include("Setup submitted for review")
    expect(response.body).not_to include("Save draft")
  end

  it "submits through the singular idempotent owner endpoint" do
    submission = build_stubbed(:onboarding_submission, hotel:, submitted_by: user)
    result = Onboarding::SubmitOnboarding::Result.success(submission:, readiness: nil)
    allow(Onboarding::SubmitOnboarding).to receive(:call).and_return(result)

    post hotel_onboarding_submission_path(hotel), params: { idempotency_key: "browser-attempt-1" }

    expect(Onboarding::SubmitOnboarding).to have_received(:call).with(
      hotel:, actor: user, idempotency_key: "browser-attempt-1"
    )
    expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "review"))
  end

  it "removes the legacy dashboard submission path" do
    post "/hotel/#{hotel.to_param}/submit_for_review"

    expect(response).to have_http_status(:not_found)
  end

  it "presents requested changes in the affected section" do
    Onboarding::InitializeProgress.new(hotel: hotel).call
    hotel.onboarding_sections.find_by!(section_key: "property_profile").update!(state: "needs_attention")
    hotel.onboarding_audit_events.create!(
      user: user,
      event_type: "changes_requested",
      section_key: "property_profile",
      metadata: { explanation: "Add a clear exterior photo." },
      occurred_at: Time.current
    )

    get hotel_onboarding_section_path(hotel, section_key: "property_profile")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Changes requested")
    expect(response.body).to include("Add a clear exterior photo.")
  end

  describe "finance phase" do
    def resolve_team_phase!
      Onboarding::InitializeProgress.new(hotel: hotel).call
      %w[property_profile property_photos roles_permissions staff_setup].each do |key|
        hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
      end
    end

    before { resolve_team_phase! }

    it "renders the taxes and fees form" do
      get hotel_onboarding_section_path(hotel, section_key: "taxes_fees")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Service Tax (SST)", "Tourism Tax (TTx)", "Add tax or fee")
      expect(response.body).to include("I confirm these are the taxes and fees this property charges")
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Taxes and fees" ])
      expect(document.css("div.overflow-y-auto h2").map { |heading| heading.text.strip })
        .to eq([ "Taxes required by law", "Property taxes and fees" ])
    end

    it "refuses to complete taxes without the confirmation" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_continue", hotel: { sst_enabled: "1", tourism_tax_enabled: "0" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Confirm that you reviewed")
      expect(hotel.onboarding_sections.find_by!(section_key: "taxes_fees").state).not_to eq("complete")
    end

    it "completes taxes and advances to room revenue" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: {
              navigation_action: "save_continue",
              confirm_taxes: "1",
              hotel: { sst_enabled: "1", tourism_tax_enabled: "0", tourism_tax_amount: "10.0" },
              tax_entries: { "0" => { name: "Heritage levy", charge_type: "charge", rate_type: "flat", amount: "5.00", enabled: "1" } }
            }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "room_revenue"))
      expect(hotel.onboarding_sections.find_by!(section_key: "taxes_fees").state).to eq("complete")
      expect(hotel.hotel_taxes.pluck(:name)).to eq([ "Heritage levy" ])
    end

    it "stores the statutory tax numbers and leaves an omitted one alone" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: {
              navigation_action: "save_draft",
              hotel: { sst_enabled: "1", tourism_tax_enabled: "1", tourism_tax_amount: "10.0",
                       sst_registration_number: " w10-1808-31000000 ", tourism_tax_registration_number: "ttx-99887766" }
            }

      expect(hotel.reload.sst_registration_number).to eq("W10-1808-31000000")
      expect(hotel.tourism_tax_registration_number).to eq("TTX-99887766")

      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_draft", hotel: { sst_enabled: "1", tourism_tax_enabled: "1", tourism_tax_amount: "12.0" } }

      expect(hotel.reload.sst_registration_number).to eq("W10-1808-31000000")
      expect(hotel.tourism_tax_registration_number).to eq("TTX-99887766")
    end

    it "locks room revenue until taxes are resolved" do
      get hotel_onboarding_section_path(hotel, section_key: "room_revenue")

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "taxes_fees"))
    end

    it "renders and completes room revenue" do
      hotel.onboarding_sections.find_by!(section_key: "taxes_fees").update!(state: "complete")

      get hotel_onboarding_section_path(hotel, section_key: "room_revenue")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Taxes and fees applied", "Posting preview")
      document = response.parsed_body
      expect(document.css("h1").map { |heading| heading.text.strip }).to eq([ "Room revenue" ])
      expect(document.css("div.overflow-y-auto h2").map { |heading| heading.text.strip })
        .to eq([ "Taxes on a room night", "If you change these later", "Stay-event policies" ])

      patch hotel_onboarding_section_path(hotel, section_key: "room_revenue"),
            params: {
              navigation_action: "save_continue",
              transaction_code: { tax_rule_keys: [ "primary:sst_tax" ] },
              hotel_transaction_configuration: { room_revenue_tax_rule_application: "new_bookings_only" }
            }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "rooms"))
      expect(hotel.onboarding_sections.find_by!(section_key: "room_revenue").state).to eq("complete")
      expect(TransactionCodes::Resolver.for(hotel).room_revenue.transaction_code_taxes.map(&:tax_rule_key))
        .to eq([ "primary:sst_tax" ])
    end

    it "rejects a tax rule that does not belong to the hotel" do
      hotel.onboarding_sections.find_by!(section_key: "taxes_fees").update!(state: "complete")
      foreign_tax = create(:hotel_tax, hotel: create(:hotel))

      patch hotel_onboarding_section_path(hotel, section_key: "room_revenue"),
            params: {
              navigation_action: "save_continue",
              transaction_code: { tax_rule_keys: [ "hotel_tax:#{foreign_tax.id}" ] }
            }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("unavailable for this hotel")
    end

    it "explains why room revenue needs attention after a tax change" do
      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_continue", confirm_taxes: "1", hotel: { sst_enabled: "1", tourism_tax_enabled: "0" } }
      patch hotel_onboarding_section_path(hotel, section_key: "room_revenue"),
            params: { navigation_action: "save_continue", transaction_code: { tax_rule_keys: [ "primary:sst_tax" ] } }

      patch hotel_onboarding_section_path(hotel, section_key: "taxes_fees"),
            params: { navigation_action: "save_continue", confirm_taxes: "1", hotel: { sst_enabled: "0", tourism_tax_enabled: "0" } }

      expect(hotel.onboarding_sections.find_by!(section_key: "room_revenue").state).to eq("needs_attention")

      get hotel_onboarding_section_path(hotel, section_key: "room_revenue")
      expect(response.body).to include("The taxes assigned to room revenue changed.")
    end
  end

  describe "rooms phase" do
    def resolve_finance_phase!
      Onboarding::InitializeProgress.new(hotel: hotel).call
      %w[property_profile property_photos roles_permissions staff_setup taxes_fees room_revenue].each do |key|
        hotel.onboarding_sections.find_by!(section_key: key).update!(state: "complete")
      end
    end

    def room_params(overrides = {})
      {
        name: "Deluxe Twin",
        max_adults: "2",
        max_children: "1",
        quantity: "2",
        no_smoking: "1",
        no_pets: "1",
        room_number_mode: "range",
        room_numbers: [ "101", "102" ]
      }.merge(overrides)
    end

    before { resolve_finance_phase! }

    it "renders the rooms-only spreadsheet and staged action sheet" do
      get hotel_onboarding_section_path(hotel, section_key: "rooms")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        "Room category", "Max adults", "Max children", "Total rooms",
        "No smoking", "No pets", "Amenities", "Manage room numbering"
      )
      expect(response.body).to include("onboarding_action_sheet", "data-controller=\"onboarding-room-grid\"")
      expect(response.body).to include("panel-multi-select", "Search room amenities")
      expect(response.body).not_to include("name=\"room_amenity_sheet[]\"")
      expect(response.body).not_to include("Standard rate", "Room group", "Photos")
      expect(response.parsed_body.at_css("[role='region'][aria-label='Room categories']")).to be_present
      expect(response.parsed_body.css("h1").map { |heading| heading.text.strip }).to eq([ "Rooms" ])
      expect(response.parsed_body.at_css("section[aria-label='Room categories']")).to be_present
      # The only h2 in the body belongs to the action sheet, which titles its own
      # dialog. The step itself is headed once, by the shell.
      expect(response.parsed_body.css("div.overflow-y-auto h2").map { |heading| heading.text.strip })
        .to eq([ "Manage room details" ])
      expect(response.parsed_body.at_css("table.panel-record-table--spreadsheet.panel-record-table--rooms")).to be_present
      expect(response.parsed_body.css("tbody > tr[data-record-table-target='row']").size).to eq(1)
      headers = response.parsed_body.css("thead th").map { |header| header.text.strip.delete_suffix("*") }
      expect(headers.last(2)).to eq([ "Room numbering", "Actions" ])
      centered_headers = response.parsed_body.css("thead th.text-center").map { |header| header.text.strip }
      expect(centered_headers).to contain_exactly("No smoking", "No pets")
      policy_checkboxes = response.parsed_body.css(
        "tbody > tr[data-record-table-target='row'] td.align-middle .flex.justify-center > .panel-checkbox[data-size='lg']"
      )
      expect(policy_checkboxes.size).to eq(2)
      action_cell = response.parsed_body.at_css("tbody > tr[data-record-table-target='row'] td:last-child")
      expect(action_cell.css("button").size).to eq(1)
      expect(action_cell.text.strip).to eq("Manage room numbering")
    end

    it "saves an inline room draft without exposing pricing" do
      patch hotel_onboarding_section_path(hotel, section_key: "rooms"), params: {
        navigation_action: "save_draft",
        room_entries: { "draft-1" => room_params }
      }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "rooms"))
      expect(hotel.room_types.sole).to have_attributes(name: "Deluxe Twin", base_price: 0.to_d)
      expect(hotel.onboarding_sections.find_by!(section_key: "rooms").state).to eq("in_progress")
    end

    it "completes rooms and advances to rates and availability" do
      patch hotel_onboarding_section_path(hotel, section_key: "rooms"), params: {
        navigation_action: "save_continue",
        room_entries: { "draft-1" => room_params }
      }

      expect(response).to redirect_to(hotel_onboarding_section_path(hotel, section_key: "rates_availability"))
      expect(hotel.onboarding_sections.find_by!(section_key: "rooms")).to have_attributes(state: "complete")
    end

    it "rejects a room id belonging to another property" do
      foreign_room = create(:room_type)

      patch hotel_onboarding_section_path(hotel, section_key: "rooms"), params: {
        navigation_action: "save_draft",
        room_entries: { "forged" => room_params(id: foreign_room.id.to_s) }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("do not belong to this property")
      expect(foreign_room.reload.name).not_to eq("Deluxe Twin")
    end

    it "rolls back a restricted room removal" do
      room = create(:room_type, hotel: hotel)
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room)

      patch hotel_onboarding_section_path(hotel, section_key: "rooms"), params: {
        navigation_action: "save_draft",
        room_entries: { "room-#{room.id}" => room_params(id: room.id.to_s, _destroy: "1") }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(RoomType.exists?(room.id)).to be(true)
      expect(response.body).to include(room.name)
    end

    it "renders persisted rooms read-only while pending review" do
      create(:room_type, hotel: hotel, name: "Garden King", quantity: 3, room_numbers: [])
      hotel.update!(status: "pending_review")

      get hotel_onboarding_section_path(hotel, section_key: "rooms")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Garden King", "Quantity only")
      expect(response.body).not_to include("Add room category", "Manage room numbering")
    end
  end

  it "does not expose another hotel's onboarding" do
    other_hotel = create(:hotel, status: "setup")

    get hotel_onboarding_path(other_hotel)

    expect(response).to redirect_to(root_path)
  end
end
