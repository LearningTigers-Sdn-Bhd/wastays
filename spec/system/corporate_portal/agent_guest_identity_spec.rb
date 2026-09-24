# frozen_string_literal: true

require "rails_helper"

# The one piece of the guest-identity fields that only exists client-side: the
# label switching between "IC" and "Passport" as the agent changes nationality,
# and the date of birth filling itself in from a Malaysian IC as it is typed.
# Everything about what the server does with those values is covered at the
# request layer (spec/requests/corporate_portal/bookings_spec.rb); this only
# proves the JavaScript that has no other way to be exercised.
RSpec.describe "Agent guest identity fields", type: :system, js: true do
  let(:user) { create(:user, :corporate) }
  let(:hotel) { create(:hotel, status: "live") }
  # The booking form is only reachable once the hotel has granted this account
  # the permission to book for its clients.
  let(:relationship) do
    create(:hotel_corporate_account, corporate_account: user.account, hotel: hotel,
                                     agent_booking_enabled: true)
  end
  let!(:room_type) do
    Rooms::SaveSeedRoomType.call!(
      hotel: hotel,
      attributes: { name: "Deluxe", room_number_mode: "custom", quantity: 2, base_price: 250.0,
                    max_adults: 2, max_children: 0, room_numbers: %w[101 102] }
    )
  end

  before do
    relationship
    sign_in_as_system(user)
    visit_when_loaded new_corporate_booking_path(
      hotel_relationship_id: relationship.id, check_in: (Date.current + 14).to_s,
      check_out: (Date.current + 16).to_s, adults: 1, rooms: 1, room_type_id: room_type.id
    )
  end

  def ic_label
    find("input[name='booking[rooms_detail][0][guests][0][government_id]']")
      .find(:xpath, "./ancestor::div[contains(@class, 'panel-form-field')][1]").find("label")
  end

  def ic_field = find("input[name='booking[rooms_detail][0][guests][0][government_id]']")
  def dob_field = find("input[name='booking[rooms_detail][0][guests][0][date_of_birth]']")

  # Sets the value and fires the same "input" event a real edit would --
  # deterministic where driving the (locale-sensitive, for the date field)
  # keyboard is not, and exactly what the controller listens for either way.
  def type_into(selector, value)
    page.execute_script(<<~JS)
      const input = document.querySelector(#{selector.to_json})
      input.value = #{value.to_json}
      input.dispatchEvent(new Event("input", { bubbles: true }))
    JS
  end

  def type_ic(value) = type_into("input[name='booking[rooms_detail][0][guests][0][government_id]']", value)
  def type_date_of_birth(value) = type_into("input[name='booking[rooms_detail][0][guests][0][date_of_birth]']", value)

  it "reads IC by default and switches to Passport for a foreign nationality" do
    expect(ic_label.text).to eq("IC")
    expect(ic_field[:placeholder]).to eq("IC number")

    page.execute_script(<<~JS)
      const select = document.querySelector("select[name='booking[rooms_detail][0][guests][0][country]']")
      select.value = "India"
      select.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    expect(ic_label).to have_text("Passport")
    expect(ic_field[:placeholder]).to eq("Passport number")
  end

  it "fills in the date of birth as a Malaysian IC is typed, and clears it if the IC becomes invalid" do
    type_ic("900101-14-5523")

    expect(dob_field.value).to eq("1990-01-01")

    # Day 99 of no month -- the first six digits no longer round-trip as a
    # real calendar date.
    type_ic("900199-14-5523")

    expect(dob_field.value).to eq("")
    expect(page).to have_text("Those first 6 digits of the IC are not a valid date of birth.")
  end

  it "rejects an IC with more than 12 digits" do
    type_ic("9001011455231")

    expect(page).to have_text("An IC number has at most 12 digits.")
  end

  # A letter used to fall out silently before the digits were ever counted, so
  # "9902031z26661zz" read as if it were "990203126661" -- a real 12-digit IC
  # -- and passed straight through.
  it "rejects an IC containing letters, rather than silently dropping them" do
    type_ic("9902031z26661zz")

    expect(page).to have_text("An IC number should contain digits only.")
    expect(dob_field.value).to eq("")
  end

  it "does not apply the IC character rule to a passport" do
    page.execute_script(<<~JS)
      const select = document.querySelector("select[name='booking[rooms_detail][0][guests][0][country]']")
      select.value = "India"
      select.dispatchEvent(new Event("change", { bubbles: true }))
    JS

    type_ic("A1234567")

    expect(page).not_to have_text("should contain digits only")
  end

  it "leaves a date of birth the agent typed themselves alone" do
    type_date_of_birth("1985-06-15")
    type_ic("900101-14-5523")

    expect(dob_field.value).to eq("1985-06-15")
  end

  it "updates the date of birth again when the agent corrects the IC to a different valid one" do
    type_ic("900101-14-5523")
    expect(dob_field.value).to eq("1990-01-01")

    type_ic("850615-14-1234")

    expect(dob_field.value).to eq("1985-06-15")
  end

  # A native date input fires "input" from merely tabbing through its day,
  # month and year segments -- with nothing actually changed. Treating that
  # alone as a manual edit would permanently stop the field from following a
  # later, genuinely different IC, which is exactly what an agent hits by
  # glancing at the auto-filled date before retyping a mistaken IC.
  it "keeps following the IC even after the date field fires a no-op input event" do
    type_ic("900101-14-5523")
    expect(dob_field.value).to eq("1990-01-01")

    dob_field.click # segment focus alone, no value change
    page.execute_script(<<~JS)
      document.querySelector("input[name='booking[rooms_detail][0][guests][0][date_of_birth]']")
        .dispatchEvent(new Event("input", { bubbles: true }))
    JS

    type_ic("850615-14-1234")

    expect(dob_field.value).to eq("1985-06-15")
  end
end
