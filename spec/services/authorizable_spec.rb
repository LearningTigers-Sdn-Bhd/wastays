# frozen_string_literal: true

require "rails_helper"

RSpec.describe Authorizable do
  let(:hotel) { create(:hotel) }

  let(:service_class) do
    Class.new do
      include Authorizable

      def permits?(actor, permission, hotel:)
        actor_permits?(actor, permission, hotel: hotel)
      end

      def permits_all?(actor, permissions, hotel:)
        actor_permits_all?(actor, permissions, hotel: hotel)
      end
    end
  end
  let(:service) { service_class.new }

  describe "#actor_permits?" do
    it "denies an absent actor" do
      expect(service.permits?(nil, "manage_folio_windows", hotel: hotel)).to be(false)
    end

    it "grants a user holding the permission at the hotel" do
      user = create(:user)
      role = create(:role, account: hotel.account)
      role.permissions << permission("manage_folio_windows", "Manage Folio Windows")
      create(:user_hotel_access, user: user, hotel: hotel, role: role)

      expect(service.permits?(user, "manage_folio_windows", hotel: hotel)).to be(true)
    end

    it "denies a user without the permission" do
      expect(service.permits?(create(:user), "manage_folio_windows", hotel: hotel)).to be(false)
    end

    it "grants a superadmin without a hotel-specific role" do
      expect(service.permits?(create(:user, :superadmin), "manage_folio_windows", hotel: hotel)).to be(true)
    end

    # The idiom this replaced was `respond_to?(:superadmin?) && superadmin?`, which
    # made authorization duck-typed: ApiKey answers superadmin? as `bearer.nil?` and
    # has no has_permission? at all, so an unbound key passed on the first clause and
    # never reached a permission lookup.
    it "raises rather than letting a non-user actor through on superadmin?" do
      api_key = ApiKey.new(bearer: nil)
      expect(api_key.superadmin?).to be(true)

      expect {
        service.permits?(api_key, "manage_folio_windows", hotel: hotel)
      }.to raise_error(Authorizable::UnsupportedActor, /ApiKey/)
    end

    it "raises for any other object that quacks like an actor" do
      impostor = Struct.new(:x) do
        def superadmin? = true
        def has_permission?(*, **) = true
      end.new(1)

      expect {
        service.permits?(impostor, "manage_folio_windows", hotel: hotel)
      }.to raise_error(Authorizable::UnsupportedActor)
    end
  end

  describe "#actor_permits_all?" do
    let(:user) { create(:user) }
    let(:role) { create(:role, account: hotel.account) }

    before { create(:user_hotel_access, user: user, hotel: hotel, role: role) }

    it "requires every permission" do
      role.permissions << permission("manage_bookings", "Manage Bookings")

      expect(service.permits_all?(user, %w[manage_bookings post_folio_corrections], hotel: hotel)).to be(false)

      role.permissions << permission("post_folio_corrections", "Post Folio Corrections")

      expect(service.permits_all?(user.reload, %w[manage_bookings post_folio_corrections], hotel: hotel)).to be(true)
    end

    it "denies an absent actor" do
      expect(service.permits_all?(nil, %w[manage_bookings], hotel: hotel)).to be(false)
    end
  end

  def permission(slug, name)
    Permission.find_or_create_by!(slug: slug) { |record| record.name = name }
  end
end
