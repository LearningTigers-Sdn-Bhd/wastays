# frozen_string_literal: true

require "rails_helper"

RSpec.describe StaffAccesses::CreateService do
  let(:hotel) { create(:hotel) }
  let(:role) { create(:role, account: hotel.account) }
  let(:email) { "new.staff@example.com" }

  def service(name: "New Staff", email: self.email, role: self.role)
    described_class.new(hotel: hotel, email: email, name: name, role: role)
  end

  it "creates active access and an encrypted temporary password without sending an invitation" do
    result = nil
    expect { result = service(email: "  NEW.STAFF@Example.COM  ").call }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)

    expect(result.success?).to be(true)
    expect(result.created).to be(true)
    expect(result.user).to have_attributes(account: hotel.account, role: "hotel_staff", name: "New Staff", email: email)
    expect(result.user.temporary_password.length).to eq(16)
    expect(result.user.authenticate(result.user.temporary_password)).to eq(result.user)
    expect(result.user.temporary_password_hotel).to eq(hotel)
    expect(result.user.ciphertext_for(:temporary_password)).not_to eq(result.user.temporary_password)
    expect(result.access).to have_attributes(hotel: hotel, user: result.user, role: role)
    expect(result.access).to be_active
    expect(hotel.staff_invitations).to be_empty
  end

  it "links existing staff without changing identity or credentials" do
    user = create(:user, account: hotel.account, email: email, name: "Existing Staff")
    attributes = user.attributes

    result = service(name: "Tampered Name").call

    expect(result.success?).to be(true)
    expect(result.created).to be(false)
    expect(result.user).to eq(user)
    expect(user.reload.attributes).to eq(attributes)
  end

  [ "sent", "unsent", "expired" ].each do |state|
    it "cancels an #{state} invitation while preserving accepted and other-property history" do
      invitation = create(:staff_invitation, hotel: hotel, account: hotel.account, email: email,
        last_sent_at: state == "unsent" ? nil : Time.current,
        expires_at: state == "expired" ? 1.day.ago : 1.day.from_now)
      accepted = create(:staff_invitation, hotel: hotel, account: hotel.account, email: email, accepted_at: Time.current)
      other = create(:staff_invitation, email: email)

      result = service.call

      expect(result.success?).to be(true)
      expect(StaffInvitation.exists?(invitation.id)).to be(false)
      expect(StaffInvitation.where(id: [ accepted.id, other.id ]).count).to eq(2)
    end
  end

  it "rolls back user creation and preserves invitations when access cannot be saved" do
    invitation = create(:staff_invitation, hotel: hotel, account: hotel.account, email: email)
    role
    invalid = UserHotelAccess.new
    invalid.errors.add(:base, "Access could not be saved")
    allow_any_instance_of(UserHotelAccess).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

    result = nil
    expect { result = service.call }.not_to change(User, :count)

    expect(result.error).to eq("Access could not be saved")
    expect(StaffInvitation.exists?(invitation.id)).to be(true)
    expect(hotel.user_hotel_accesses).to be_empty
  end

  it "preserves outstanding invitations on invalid user input" do
    invitation = create(:staff_invitation, hotel: hotel, account: hotel.account, email: email)
    result = service(name: "").call

    expect(result.success?).to be(false)
    expect(result.error).to include("Name")
    expect(User.exists?(email: email)).to be(false)
    expect(StaffInvitation.exists?(invitation.id)).to be(true)
  end

  it "rejects roles from another account" do
    result = service(role: create(:role)).call

    expect(result.success?).to be(false)
    expect(User.exists?(email: email)).to be(false)
  end

  it "rechecks current eligibility and preserves active or revoked access" do
    user = create(:user, account: hotel.account, email: email)
    access = create(:user_hotel_access, user: user, hotel: hotel, role: role)

    [ nil, 1.day.ago ].each do |deactivated_at|
      access.update!(deactivated_at: deactivated_at)
      attributes = access.attributes
      expect(service.call.success?).to be(false)
      expect(access.reload.attributes).to eq(attributes)
    end
  end

  it "rejects an ineligible login at submission" do
    user = create(:user, :corporate, email: email)

    result = service.call

    expect(result.success?).to be(false)
    expect(user.user_hotel_accesses).to be_empty
  end

  it "prevents a new invitation after direct access is granted" do
    result = service.call
    invitation = StaffInvitations::CreateService.new(hotel: hotel, invited_by: result.user,
      email: email, role: role).call

    expect(invitation.success?).to be(false)
    expect(invitation.error).to include("already has active access")
    expect(hotel.staff_invitations.reload).to be_empty
    expect(result.access.reload.role).to eq(role)
  end

  it "preserves access when an invitation was accepted before direct addition" do
    invitation = create(:staff_invitation, hotel: hotel, account: hotel.account, email: email)
    user = create(:user, account: hotel.account, email: email)
    invitation.accept!(user)

    result = service.call

    expect(result.success?).to be(false)
    expect(invitation.reload).to be_accepted
    expect(user.user_hotel_accesses.find_by!(hotel: hotel).role).to eq(invitation.role)
  end

  it "returns a friendly error for a database email collision" do
    role
    allow(User).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

    result = service.call

    expect(result.success?).to be(false)
    expect(result.error).to include("This email is already in use")
    expect(hotel.user_hotel_accesses).to be_empty
  end
end
