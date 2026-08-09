require 'rails_helper'

RSpec.describe 'HotelPortal::RatePlans', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: 'admin') }
  let(:hotel) { create(:hotel, account: account, status: 'live') }
  let(:role) { create(:role, account: account, slug: 'hotel_owner', name: 'Hotel Owner') }
  let!(:room_type) { create(:room_type, hotel: hotel) }

  before do
    Permission.find_or_create_by!(slug: 'manage_hotel_profile') { |permission| permission.name = 'Manage Hotel Profile' }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: 'manage_hotel_profile'))
    UserRole.create!(user: user, role: role)
    UserHotelAccess.create!(user: user, hotel: hotel, role: role)
    sign_in_as(user)
  end

  def delete_action_labels(body)
    Nokogiri::HTML(body).css('a[data-turbo-method="delete"]').map { |link| link.text.strip }
  end

  describe 'GET /hotel/:hotel_id/rate_plans/new' do
    it "redirects retired wizard bookmarks to the flat form" do
      get "/hotel/#{hotel.to_param}/rate_plans/wizard"

      expect(response).to redirect_to(new_hotel_rate_plan_path(hotel))
      expect(response).to have_http_status(:moved_permanently)
    end

    it 'renders the create form in a sheet' do
      get new_hotel_rate_plan_path(hotel)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("New rate plan")
      expect(Nokogiri::HTML(response.body).at_css('turbo-frame#settings_action_sheet dialog')).to be_present
    end

    it 'uses autocomplete and one room selector as the pricing context' do
      other_room = create(:room_type, hotel: hotel, name: "Grand Villa", max_adults: 12)

      get new_hotel_rate_plan_path(hotel, room_type_id: other_room.id)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#rate_plan_name-autocomplete')).to be_present
      selector = doc.at_css('select[name="rate_plan[room_type_id]"]')
      expect(selector.at_css('option[selected]')["value"]).to eq(other_room.id.to_s)
      expect(doc.css('[name^="room_pricing[prices]"]').size).to eq(0)
      expect(response.body).to include("Pricing for Grand Villa")
    end

    it 'renders only the selected room occupancy ladder in per-guest mode' do
      hotel.update!(sell_mode: "per_person")
      room_type.update!(max_adults: 2)
      villa = create(:room_type, hotel: hotel, name: "Grand Villa", max_adults: 12)

      get new_hotel_rate_plan_path(hotel, room_type_id: villa.id)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css('[name^="room_pricing[prices]"]').size).to eq(12)
      expect(doc.at_css('[name="room_pricing[prices][12]"]')).to be_present
      expect(doc.at_css('[name="room_pricing[prices][13]"]')).to be_nil
      expect(response.body).not_to include("Pricing for #{room_type.name}")
    end

    it 'renders an age band template the add button can actually clone' do
      hotel.update!(sell_mode: 'per_person')

      get new_hotel_rate_plan_path(hotel)

      # fields_for captures rather than writes, so an ERB <% here leaves the
      # <template> empty and the add button silently appends nothing.
      expect(response.body).to include('rate_plan[rate_plan_age_bands_attributes][NEW_RECORD][min_age]')
    end

    it 'shows the hotel charging model and default currency as inherited context' do
      hotel.update!(sell_mode: 'per_person', default_currency: 'USD')

      get new_hotel_rate_plan_path(hotel)

      context = Nokogiri::HTML(response.body).at_css('dl[aria-label="Property-controlled rate plan settings"]')
      expect(context.text.squish).to include('How the property charges Price per guest')
      expect(context.text.squish).to include('Currency USD')
      expect(Nokogiri::HTML(response.body).at_css('#rate_plan_sell_mode')).to be_nil
    end

    it 'explains the current distribution limit for a connected per-guest hotel' do
      hotel.update!(sell_mode: 'per_person', preferred_channel_manager: 'channex')

      get new_hotel_rate_plan_path(hotel)

      expect(response.body).to include('Per-guest rates are not distributed yet')
      expect(response.body).to include('Room availability continues to sync')
    end
  end

  describe 'GET /hotel/:hotel_id/rate_plans/:id/edit' do
    let!(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: 'Promo Rate') }

    it 'renders a non-dismissible full bottom sheet as one form without tabs' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to have_http_status(:ok)
      doc = Nokogiri::HTML(response.body)
      sheet = doc.at_css('turbo-frame#settings_action_sheet dialog#edit-rate-plan-sheet')
      expect(sheet).to be_present
      expect(sheet["class"]).to include("h-dvh")
      expect(sheet["data-panels-ui-sheet-side"]).to eq("bottom")
      expect(sheet["data-panels-ui--sheet-dismissible-value"]).to eq("false")
      expect(doc.at_css("form#edit-rate-plan-#{rate_plan.id}-form")).to be_present
      expect(doc.css('[role="tab"]')).to be_empty
      expect(doc.text.squish).to include("Plan details")
      expect(doc.text.squish).to include("Room pricing")
      expect(doc.at_css('dialog[role="alertdialog"]')).to be_present
      expect(response.body).to include("Promo Rate")
    end

    it 'never asks the operator how the plan is charged — the property decides' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(Nokogiri::HTML(response.body).at_css('select#rate_plan_sell_mode')).to be_nil
    end

    it 'shows only the per-room occupancy fields at a per-room hotel' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#rate_plan_base_occupancy')).to be_present
      expect(doc.at_css('#rate_plan_extra_pax_charge')).to be_present
      expect(doc.at_css('#rate_plan_single_supplement')).to be_nil
      expect(doc.text.squish).to include('Guests included')
      expect(doc.text.squish).to include('Extra guest charge')
    end

    it 'shows only the per-guest fields at a per-guest hotel' do
      hotel.update!(sell_mode: "per_person")
      per_person_plan = create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: 'Family Plan')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#rate_plan_single_supplement')).to be_nil
      expect(doc.at_css('#rate_plan_child_price_multiplier')).to be_present
      expect(doc.at_css('#rate_plan_base_occupancy')).to be_nil
      expect(doc.text.squish).to include('Default child price')
      expect(doc.text.squish).to include("Child pricing")
    end

    it 'shows a delete action when the plan has no bookings' do
      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(delete_action_labels(response.body)).to include("Delete")
    end

    it 'hides the delete action once the plan has a booking' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(delete_action_labels(response.body)).to be_empty
    end

    it 'shows per-room-type pricing mode controls, pre-filled from existing derived pricing' do
      rate_plan.room_type_rate_plans.sole.update!(pricing_mode: "multiplier", pricing_value: -15)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response.body).to include("Adjust Standard Rate")
      expect(response.body).to include('name="room_pricing[derive_mode]"')
      expect(response.body).to include('value="-15.0"')
    end

    it 'wires up a live price preview per room type, anchored to that room type\'s own Standard Rate' do
      rate_plan.room_type_rate_plans.sole.update!(pricing_mode: "fixed", pricing_value: 100)

      get edit_hotel_rate_plan_path(hotel, rate_plan)

      expect(response.body).to include('data-controller="rate-plan-room-pricing"')
      expect(response.body).to include("data-rate-plan-room-pricing-anchor-value=\"#{room_type.base_price.to_f}\"")
      expect(response.body).to include('data-rate-plan-room-pricing-target="preview"')
    end

    it 'wires up a live price preview for each age band, using the room type Standard Rate and a mode choice' do
      hotel.update!(sell_mode: 'per_person')
      per_person_plan = create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: 'Family Plan', currency: 'MYR')
      create(:rate_plan_age_band, rate_plan: per_person_plan, min_age: 4, max_age: 11, price_value: 40, label: 'Child')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      expect(response.body).to include('data-controller="rate-plan-age-bands age-band-price-preview"')
      expect(response.body).to include('data-age-band-price-preview-currency-value="MYR"')
      expect(response.body).not_to include('data-age-band-price-preview-target="roomTypeField"')
      expect(response.body).to include('data-role="price-preview"')
      expect(response.body).to include('Fixed price per child')
    end

    it 'shows child pricing guidance and the add button when there are no age groups yet' do
      hotel.update!(sell_mode: 'per_person')
      per_person_plan = create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: 'Family Plan', currency: 'MYR')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      empty_state = Nokogiri::HTML(response.body).at_css('[data-rate-plan-age-bands-target="emptyState"]')
      expect(empty_state.text).to include('No age groups yet')
      expect(empty_state["class"]).not_to include("hidden")
      expect(response.body).to include('Add age group')
    end

    it 'hides the empty-state add button once age groups already exist' do
      hotel.update!(sell_mode: 'per_person')
      per_person_plan = create(:rate_plan, :custom, hotel: hotel, room_type: room_type, name: 'Family Plan', currency: 'MYR')
      create(:rate_plan_age_band, rate_plan: per_person_plan, min_age: 4, max_age: 11, price_value: 40, label: 'Child')

      get edit_hotel_rate_plan_path(hotel, per_person_plan)

      empty_state = Nokogiri::HTML(response.body).at_css('[data-rate-plan-age-bands-target="emptyState"]')
      expect(empty_state["class"]).to include("hidden")
    end

    it "uses the same shell for Standard Rate while locking its identity and room membership" do
      standard = room_type.standard_rate_plan

      get edit_hotel_rate_plan_path(hotel, standard)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#rate_plan_name')).to be_nil
      expect(doc.text.squish).to include("Standard Rate follows the room category")
      expect(doc.text.squish).to include(room_type.name)
      expect(doc.text.squish).not_to include("Remove #{room_type.name}")
      expect(delete_action_labels(response.body)).to be_empty
    end

    it "allows Standard Rate occupancy and child pricing for a per-guest hotel" do
      hotel.update!(sell_mode: "per_person")
      room_type.update!(max_adults: 2)
      standard = room_type.standard_rate_plan
      assignment = standard.room_type_rate_plans.sole
      assignment.occupancy_prices.create!(adults: 1, price: 180)
      assignment.occupancy_prices.create!(adults: 2, price: 300)

      get edit_hotel_rate_plan_path(hotel, standard)

      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('#rate_plan_name')).to be_nil
      expect(doc.at_css('[name="room_pricing[prices][1]"]')["value"]).to eq("180.0")
      expect(doc.at_css('[name="room_pricing[prices][2]"]')["value"]).to eq("300.0")
      expect(doc.text.squish).to include("Child pricing")
    end
  end

  describe 'POST /hotel/:hotel_id/rate_plans' do
    it 'creates a new rate plan and configures one selected room category' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            name: 'Flexible Breakfast Rate',
            room_type_id: room_type.id,
            base_occupancy: 2,
            extra_pax_charge: 50.0
          },
          room_pricing: { rate_mode: "manual", default_rate: "120" }
        }
      }.to change(RatePlan, :count).by(1)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      follow_redirect!
      expect(response.body).to include("created successfully")

      rate_plan = RatePlan.last
      expect(rate_plan.name).to eq('Flexible Breakfast Rate')
      expect(rate_plan.room_types).to include(room_type)
      expect(rate_plan.room_type_rate_plans.find_by(room_type: room_type).pricing_value).to eq(120.to_d)
    end

    it 'uses a selected existing plan without changing its shared details' do
      existing = create(:rate_plan, :custom, hotel: hotel, name: "Advance Purchase", description: "Shared terms")

      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            rate_plan_id: existing.id,
            name: "Advance Purchase",
            description: "Should not replace shared terms",
            room_type_id: room_type.id
          },
          room_pricing: { rate_mode: "manual", default_rate: "145" }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(existing.reload.description).to eq("Shared terms")
      expect(existing.room_type_rate_plans.sole).to have_attributes(room_type: room_type, pricing_value: 145.to_d)
    end

    it "keeps an invalid selected-plan submission on the create endpoint" do
      existing = create(:rate_plan, :custom, hotel: hotel, name: "Advance Purchase")

      post hotel_rate_plans_path(hotel), params: {
        rate_plan: {
          rate_plan_id: existing.id,
          name: existing.name,
          room_type_id: room_type.id
        },
        room_pricing: { rate_mode: "manual", default_rate: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      form = response.parsed_body.at_css("form#new-rate-plan-form")
      expect(form["action"]).to eq(hotel_rate_plans_path(hotel))
      expect(form["method"]).to eq("post")
      expect(existing.room_type_rate_plans).to be_empty
    end

    it 'takes the sell mode from the hotel' do
      hotel.update!(sell_mode: 'per_person')
      room_type.update!(max_adults: 2)

      post hotel_rate_plans_path(hotel), params: {
        rate_plan: {
          name: 'Smuggled Per Room',
          sell_mode: 'per_room',
          room_type_id: room_type.id
        },
        room_pricing: { rate_mode: "manual", prices: { "1" => "100", "2" => "180" } }
      }

      expect(RatePlan.last.sell_mode).to eq('per_person')
      expect(RatePlan.last.room_type_rate_plans.sole.occupancy_prices.order(:adults).pluck(:price)).to eq([ 100.to_d, 180.to_d ])
    end

    it 'stores a separate starting price for each supported adult occupancy' do
      hotel.update!(sell_mode: 'per_person')
      room_type.update!(max_adults: 2)

      post hotel_rate_plans_path(hotel), params: {
        rate_plan: {
          name: 'Per Guest Flexible',
          room_type_id: room_type.id
        },
        room_pricing: { rate_mode: "manual", prices: { "1" => "180", "2" => "300" } }
      }

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      assignment = RatePlan.last.room_type_rate_plans.sole
      expect(assignment.occupancy_prices.order(:adults).pluck(:adults, :price)).to eq([
        [ 1, 180.to_d ],
        [ 2, 300.to_d ]
      ])
    end

    it 'requires every adult occupancy supported by the room category' do
      hotel.update!(sell_mode: 'per_person')
      room_type.update!(max_adults: 2)

      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            name: 'Incomplete Per Guest Plan',
            room_type_id: room_type.id
          },
          room_pricing: { rate_mode: "manual", prices: { "1" => "180", "2" => "" } }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter a price for 2 adults")
    end

    it 'rejects a rate plan without a room category' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: { name: 'Unassigned Plan' },
          room_pricing: { rate_mode: "manual", default_rate: "120" }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Select a room category")
    end

    it 'creates a room type rate plan with derived multiplier pricing' do
      post hotel_rate_plans_path(hotel), params: {
        rate_plan: {
          name: 'Non-Refundable',
          room_type_id: room_type.id
        },
        room_pricing: { rate_mode: "derived", derive_mode: "multiplier", derive_value: "-10" }
      }

      rate_plan = RatePlan.last
      rtrp = rate_plan.room_type_rate_plans.find_by(room_type: room_type)
      expect(rtrp.pricing_mode).to eq('multiplier')
      expect(rtrp.pricing_value.to_f).to eq(-10.0)
    end

    it 'requires a starting price when staff set prices by date' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            name: 'Flexible',
            room_type_id: room_type.id
          },
          room_pricing: { rate_mode: "manual", default_rate: "" }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.text).to include("Default rate can't be blank")
    end

    it 're-renders with errors when derived pricing is missing its value' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: {
            name: 'Non-Refundable',
            room_type_id: room_type.id
          },
          room_pricing: { rate_mode: "derived", derive_mode: "multiplier", derive_value: "" }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.text).to include("Derive value can't be blank")
    end

    it 're-renders the form with errors when invalid' do
      expect {
        post hotel_rate_plans_path(hotel), params: {
          rate_plan: { name: '', room_type_id: room_type.id },
          room_pricing: { rate_mode: "manual", default_rate: "120" }
        }
      }.not_to change(RatePlan, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "unified editor saves" do
    let!(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, room_type: room_type) }
    let(:turbo_headers) { { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => "settings_action_sheet" } }

    it "saves shared details and selected-room pricing in one transaction" do
      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: {
          name: "Advance purchase",
          description: "Pay before arrival",
          room_type_id: room_type.id
        },
        room_pricing: { rate_mode: "manual", default_rate: "225" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Mime[:turbo_stream].to_s)
      expect(response.body).to include('target="settings_action_sheet"')
      expect(response.body).not_to include('action="complete_sheet"')
      expect(rate_plan.reload).to have_attributes(name: "Advance purchase", description: "Pay before arrival")
      expect(rate_plan.room_type_rate_plans.sole.pricing_value).to eq(225.to_d)
    end

    it "saves child pricing and only the selected room occupancy matrix" do
      hotel.update!(sell_mode: "per_person")
      room_type.update!(max_adults: 2)

      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: {
          name: "Family offer",
          room_type_id: room_type.id,
          child_price_multiplier: "0.5",
          rate_plan_age_bands_attributes: {
            "0" => { label: "Child", min_age: "3", max_age: "12", pricing_mode: "amount", price_value: "40" }
          }
        },
        room_pricing: { rate_mode: "manual", prices: { "1" => "180", "2" => "300" } }
      }, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(rate_plan.reload.name).to eq("Family offer")
      expect(rate_plan.child_price_multiplier).to eq(0.5.to_d)
      expect(rate_plan.rate_plan_age_bands.sole).to have_attributes(label: "Child", min_age: 3, max_age: 12)
      expect(rate_plan.room_type_rate_plans.sole.occupancy_prices.order(:adults).pluck(:price)).to eq([ 180.to_d, 300.to_d ])
    end

    it "keeps Standard Rate identity locked while saving its per-guest room pricing" do
      hotel.update!(sell_mode: "per_person")
      room_type.update!(max_adults: 2)
      standard = room_type.standard_rate_plan

      patch hotel_rate_plan_path(hotel, standard), params: {
        rate_plan: { name: "Renamed", room_type_id: room_type.id, child_price_multiplier: "0.5" },
        room_pricing: { rate_mode: "manual", prices: { "1" => "180", "2" => "300" } }
      }, headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(standard.reload.name).to eq("Standard Rate")
      expect(standard.room_type_rate_plans.sole.occupancy_prices.count).to eq(2)
    end

    it "rolls back shared fields when selected-room pricing is invalid" do
      patch hotel_rate_plan_path(hotel, rate_plan), params: {
        rate_plan: { name: "Changed", room_type_id: room_type.id },
        room_pricing: { rate_mode: "manual", default_rate: "" }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css('[data-rate-plan-editor-error-summary][tabindex="-1"]')).to be_present
      expect(rate_plan.reload.name).not_to eq("Changed")
    end
  end

  describe "selected-room context" do
    let!(:rate_plan) { create(:rate_plan, :custom, hotel: hotel, room_type: room_type) }
    let(:turbo_headers) { { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => "settings_action_sheet" } }

    # A per-room plan prices the room once, so the preview must not walk adult
    # counts and imply an occupancy matrix the plan does not have.
    it "tells the preview whether this property prices per guest" do
      get edit_hotel_rate_plan_path(hotel, rate_plan)
      expect(response.body).to include('data-rate-plan-room-pricing-per-person-value="false"')

      hotel.update!(sell_mode: "per_person")
      get edit_hotel_rate_plan_path(hotel, rate_plan)
      expect(response.body).to include('data-rate-plan-room-pricing-per-person-value="true"')
    end

    it "offers one select menu containing only attached room categories" do
      attached_room = create(:room_type, hotel: hotel, name: "Garden villa")
      unattached_room = create(:room_type, hotel: hotel, name: "Pool villa")
      create(:room_type_rate_plan, rate_plan: rate_plan, room_type: attached_room, pricing_value: 200)

      get edit_hotel_rate_plan_path(hotel, rate_plan, room_type_id: attached_room.id)

      doc = Nokogiri::HTML(response.body)
      selector = doc.at_css('select[name="rate_plan[room_type_id]"]')
      expect(selector.css("option").map { |option| option["value"] }).to contain_exactly(room_type.id.to_s, attached_room.id.to_s)
      expect(selector.at_css('option[selected]')["value"]).to eq(attached_room.id.to_s)
      expect(response.body).not_to include(unattached_room.name)
    end

    it "renders only the selected room's per-guest occupancy fields" do
      hotel.update!(sell_mode: "per_person")
      room_type.update!(max_adults: 2)
      villa = create(:room_type, hotel: hotel, name: "Grand villa", max_adults: 12)
      create(:room_type_rate_plan, rate_plan: rate_plan, room_type: villa)

      get edit_hotel_rate_plan_path(hotel, rate_plan, room_type_id: villa.id)

      doc = Nokogiri::HTML(response.body)
      expect(doc.css('[name^="room_pricing[prices]"]').size).to eq(12)
      expect(doc.at_css('[name="room_pricing[prices][12]"]')).to be_present
      expect(response.body).not_to include("Pricing for #{room_type.name}")
    end

    it "rejects an unassigned room context" do
      other_room = create(:room_type, hotel: hotel, name: "Garden villa")

      expect {
        get edit_hotel_rate_plan_room_pricing_path(hotel, rate_plan, other_room)
      }.not_to change(RoomTypeRatePlan, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "does not create an assignment through the pricing editor" do
      other_room = create(:room_type, hotel: hotel, name: "Garden villa")

      expect {
        put hotel_rate_plan_room_pricing_path(hotel, rate_plan, other_room), params: {
          room_pricing: { rate_mode: "manual", default_rate: "240" }
        }, headers: turbo_headers
      }.not_to change(RoomTypeRatePlan, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "returns the selected room and validation errors for an incomplete per-guest matrix" do
      hotel.update!(sell_mode: "per_person")
      room_type.update!(max_adults: 2)

      put hotel_rate_plan_room_pricing_path(hotel, rate_plan, room_type), params: {
        room_pricing: { rate_mode: "manual", prices: { "1" => "180", "2" => "" } }
      }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Enter a price for 2 adults")
      expect(response.body).to include("data-rate-plan-editor-room-type-id-value=\"#{room_type.id}\"")
    end

    it "removes an eligible room immediately and keeps the editor open" do
      other_room = create(:room_type, hotel: hotel, name: "Garden villa")
      create(:room_type_rate_plan, rate_plan: rate_plan, room_type: other_room, pricing_value: 200)

      delete hotel_rate_plan_room_pricing_path(hotel, rate_plan, other_room), headers: turbo_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('target="settings_action_sheet"')
      expect(rate_plan.reload.room_types).to contain_exactly(room_type)
    end

    it "blocks removal of the final room" do
      delete hotel_rate_plan_room_pricing_path(hotel, rate_plan, room_type), headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("must keep at least one room category")
      expect(rate_plan.reload.room_types).to contain_exactly(room_type)
    end

    it "blocks removal when a matching booking uses the room and plan" do
      other_room = create(:room_type, hotel: hotel, name: "Garden villa")
      create(:room_type_rate_plan, rate_plan: rate_plan, room_type: other_room, pricing_value: 200)
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      delete hotel_rate_plan_room_pricing_path(hotel, rate_plan, room_type), headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("existing bookings use this rate plan")
      expect(rate_plan.reload.room_types).to include(room_type)
    end
  end

  describe 'DELETE /hotel/:hotel_id/rate_plans/:id' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom') }

    it 'deletes custom rate plan' do
      expect {
        delete hotel_rate_plan_path(hotel, rate_plan)
      }.to change(RatePlan, :count).by(-1)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
    end

    it 'prevents deleting standard rate plan' do
      standard_rate = hotel.rate_plans.find_by(name: 'Standard Rate') || create(:rate_plan, hotel: hotel, name: 'Standard Rate')

      expect {
        delete hotel_rate_plan_path(hotel, standard_rate)
      }.not_to change(RatePlan, :count)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(flash[:alert]).to include("cannot be deleted")
    end

    it 'prevents deleting a rate plan that has existing bookings' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      expect {
        delete hotel_rate_plan_path(hotel, rate_plan)
      }.not_to change(RatePlan, :count)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(flash[:alert]).to include("cannot be deleted")
    end
  end

  describe 'PATCH /hotel/:hotel_id/rate_plans/:id/archive' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom') }

    it 'archives a custom rate plan, including one with existing bookings' do
      booking = create(:booking, hotel: hotel)
      create(:booking_room, booking: booking, room_type: room_type, rate_plan: rate_plan)

      patch archive_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(rate_plan.reload.archived?).to be true
    end

    # The registry's Archive button targets _top and the editor's targets the
    # sheet, but both send a turbo_stream Accept header. Only the frame tells
    # "navigate the page" apart from "stay in the sheet".
    it 'navigates the page when archiving from the settings registry' do
      patch archive_hotel_rate_plan_path(hotel, rate_plan), headers: { "Accept" => Mime[:turbo_stream].to_s }

      expect(response.body).to include('action="complete_sheet"')
      expect(response.body).not_to include('edit-rate-plan-sheet')
    end

    it 'stays in the sheet when archiving from the editor' do
      patch archive_hotel_rate_plan_path(hotel, rate_plan),
        headers: { "Accept" => Mime[:turbo_stream].to_s, "Turbo-Frame" => "settings_action_sheet" }

      expect(response.body).to include('edit-rate-plan-sheet')
      expect(response.body).not_to include('action="complete_sheet"')
      expect(rate_plan.reload.archived?).to be true
    end

    it 'prevents archiving the standard rate plan' do
      standard_rate = hotel.rate_plans.find_by(name: 'Standard Rate') || create(:rate_plan, hotel: hotel, name: 'Standard Rate')

      patch archive_hotel_rate_plan_path(hotel, standard_rate)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(flash[:alert]).to include("cannot be archived")
      expect(standard_rate.reload.archived?).to be false
    end

    it 'excludes an archived rate plan from availability search results' do
      create(:room_type_rate_plan, room_type: room_type, rate_plan: rate_plan)
      rate_plan.archive!

      service = BookingEngine::AvailabilityService.new(check_in: Date.tomorrow, check_out: Date.tomorrow + 2.days, adults: 2)
      options = service.send(:candidate_rate_plans_for, room_type)

      expect(options).not_to include(rate_plan)
    end
  end

  describe 'PATCH /hotel/:hotel_id/rate_plans/:id/unarchive' do
    let!(:rate_plan) { create(:rate_plan, hotel: hotel, name: 'Promo Rate', kind: 'custom', archived_at: Time.current) }

    it 'restores an archived rate plan' do
      patch unarchive_hotel_rate_plan_path(hotel, rate_plan)

      expect(response).to redirect_to(hotel_room_types_path(hotel))
      expect(rate_plan.reload.archived?).to be false
    end
  end
end
