# frozen_string_literal: true

# Shared permission check for services that gate a folio operation.
#
# Ten services carried near-identical copies of this:
#
#   @user&.respond_to?(:superadmin?) && @user.superadmin? ||
#     @user&.respond_to?(:has_permission?) && @user.has_permission?(PERMISSION, hotel: @hotel)
#
# Two things are wrong with it.
#
# The superadmin? clause is dead weight: User#has_permission? already returns true
# for a superadmin, so for a User the second clause alone gives the same answer.
# The only actor the first clause can decide on its own is a non-User.
#
# Which is the real problem — respond_to? turns authorization into duck typing, so
# anything that quacks becomes an admin. ApiKey answers superadmin? as `bearer.nil?`
# and has no has_permission? at all, so an unbound key would pass on the first clause
# and never reach a permission lookup. No live path does that today; the guard enables
# it rather than preventing it.
#
# These actors are Users. booking_folios.created_by_id and closed_by_id are foreign
# keys to users, so the database rejects anything else regardless. Absent actor stays
# denied, exactly as before — system callers reach these paths through their own
# explicit flags (system_posting, skip_authorization), not by being mistaken for an
# administrator. A non-User actor now raises at the boundary instead of silently
# passing.
module Authorizable
  class UnsupportedActor < StandardError; end

  private

  def actor_permits?(actor, permission, hotel:)
    return false if actor.nil?
    raise UnsupportedActor, "#{actor.class} cannot hold permissions" unless actor.is_a?(User)

    actor.has_permission?(permission, hotel: hotel)
  end

  def actor_permits_all?(actor, permissions, hotel:)
    permissions.all? { |permission| actor_permits?(actor, permission, hotel: hotel) }
  end
end
