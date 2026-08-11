# frozen_string_literal: true

class OtaFinancialSettingsPolicy < ApplicationPolicy
  def show?
    manage_financial_settings?
  end

  def update?
    manage_financial_settings?
  end

  def approve_adjustment?
    manage_financial_settings? && (user.superadmin? || user.has_permission?("post_folio_adjustments", hotel: record))
  end

  private

  def manage_financial_settings?
    user.superadmin? || user.has_permission?("manage_general_ledger_maps", hotel: record)
  end
end
