# Idempotent. Mirrors WAStays_Pricing.png. "Pro" column => "Plus".
plan_defs = [
  { slug: "easy",       name: "Easy",       position: 1, most_popular: false },
  { slug: "direct",     name: "Direct",     position: 2, most_popular: false },
  { slug: "core",       name: "Core",       position: 3, most_popular: false },
  { slug: "plus",       name: "Plus",       position: 4, most_popular: true  },
  { slug: "enterprise", name: "Enterprise", position: 5, most_popular: false }
].freeze

group_defs = {
  "aic"    => [ "AI Concierge (AIC)", 1 ],
  "be"     => [ "Booking Engine (BE)", 2 ],
  "cm"     => [ "Channel Manager (CM)", 3 ],
  "pms"    => [ "Property Management System (PMS)", 4 ],
  "rate"   => [ "Rate Management", 5 ],
  "hk"     => [ "Housekeeping", 6 ],
  "guest"  => [ "Guest Database & Profile", 7 ],
  "report" => [ "Reporting", 8 ],
  "comms"  => [ "Communication & Notifications", 9 ],
  "system" => [ "System & Access Control", 10 ],
  "addons" => [ "Add-ons", 11 ]
}.freeze

plan_feature_defs = [
  # AIC
  [ "aic", "whatsapp_automation_flows", "WhatsApp automation flows", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "llm_hotels_resorts_homestays", "LLM — hotels, resorts & homestays", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "guest_engagement_flow", "Guest engagement flow", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "ai_concierge_flow", "AI concierge flow", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "activity_offers_flow", "Activity & offers flow", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "housekeeping_flow", "Housekeeping flow", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "complaint_system_flow", "Complaint system flow", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "aic", "ai_concierge_page", "AI Concierge Page", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  # BE
  [ "be", "payment_system", "Payment system", false, false,
    { "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "be", "billing_invoicing_system", "Billing & invoicing system", false, false,
    { "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "be", "direct_booking_flow", "Direct booking flow", false, false,
    { "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "be", "folio_management_billing", "Folio Management & Billing", false, false,
    { "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  # CM
  [ "cm", "manage_40_otas", "Manage 40+ OTAs at one go", false, false,
    { "plus"=>true, "enterprise"=>true } ],
  [ "cm", "auto_sync_availability", "Auto-sync availability across OTAs & direct", false, false,
    { "plus"=>true, "enterprise"=>true } ],
  # PMS
  [ "pms", "reservation_management", "Reservation Management", true, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "pms", "room_management_availability", "Room Management & Availability", true, false,
    { "core"=>"room_allotment", "plus"=>true, "enterprise"=>true } ],
  [ "pms", "front_desk_operations", "Front Desk Operations", true, false,
    { "core"=>"basic", "plus"=>"basic", "enterprise"=>"advanced" } ],
  # Rate Management
  [ "rate", "rate_plan_hierarchy", "Rate plan hierarchy", true, false,
    { "core"=>"basic", "plus"=>"basic", "enterprise"=>"full" } ],
  [ "rate", "date_range_dow_pricing", "Date-range & day-of-week pricing", true, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "rate", "rate_override_reason_code", "Rate override with reason code", false, false,
    { "enterprise"=>true } ],
  [ "rate", "min_max_stay_rules", "Min/max stay rules", false, false,
    { "enterprise"=>true } ],
  [ "rate", "last_minute_rate_automation", "Last-minute rate automation", false, false,
    { "enterprise"=>true } ],
  [ "rate", "instant_rate_sync", "Instant rate sync", false, false,
    { "enterprise"=>true } ],
  # Housekeeping
  [ "hk", "task_assignment_minibar_log", "Task assignment & minibar log", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "hk", "maintenance_request_tracking", "Maintenance request tracking", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "hk", "room_status_board", "Room status board", false, false,
    { "enterprise"=>true } ],
  [ "hk", "priority_room_flagging", "Priority room flagging", false, false,
    { "enterprise"=>true } ],
  # Guest DB
  [ "guest", "unified_guest_profile", "Unified guest profile", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "guest", "preference_tagging", "Preference tagging", false, false,
    { "enterprise"=>true } ],
  [ "guest", "complaint_history", "Complaint history", false, false,
    { "enterprise"=>true } ],
  [ "guest", "vip_blacklist_flag", "VIP & Blacklist flag", false, false,
    { "enterprise"=>true } ],
  [ "guest", "whatsapp_linked_to_profile", "WhatsApp number linked to profile", false, false,
    { "enterprise"=>true } ],
  # Reporting
  [ "report", "daily_occupancy_revenue", "Daily occupancy & revenue report", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "report", "arrivals_departures_list", "Arrivals & departures list", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "report", "outstanding_balance_noshow", "Outstanding balance / no-show / cancellation", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "report", "excel_pdf_export", "Excel / PDF export", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "report", "housekeeper_productivity", "Housekeeper productivity report", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "report", "booking_source_analysis", "Booking source analysis", false, false,
    { "plus"=>true, "enterprise"=>true } ],
  [ "report", "revenue_allocation_per_night", "Revenue allocation (per night)", false, false,
    { "enterprise"=>true } ],
  [ "report", "backdated_checkin_rate", "Backdated check-in & rate report", false, false,
    { "enterprise"=>true } ],
  # Comms
  [ "comms", "welcoming_instay_messaging", "Welcoming & in-stay messaging", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "comms", "checkout_receipt_review", "Check-out receipt & review request", false, false,
    { "easy"=>true, "direct"=>true, "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "comms", "automated_prearrival", "Automated pre-arrival WhatsApp/email", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "comms", "checkin_confirmation", "Check-in confirmation message", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "comms", "internal_staff_alerts", "Internal staff alerts", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  # System & Access
  [ "system", "role_based_access_control", "Role-based access control", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "system", "no_show_auto_handling", "No-show auto-handling", false, false,
    { "core"=>true, "plus"=>true, "enterprise"=>true } ],
  [ "system", "full_audit_trail", "Full audit trail", false, false,
    { "enterprise"=>true } ],
  [ "system", "multi_property_view", "Multi-property view", false, false,
    { "enterprise"=>true } ],
  [ "system", "shift_handover_log", "Shift handover log", false, false,
    { "enterprise"=>true } ],
  # Add-ons
  [ "addons", "live_chat", "Live chat", false, true,
    { "easy"=>:addon, "direct"=>:addon, "core"=>:addon, "plus"=>:addon, "enterprise"=>:addon } ],
  [ "addons", "e_invoice", "E-invoice", false, true,
    { "core"=>:addon, "plus"=>:addon, "enterprise"=>:addon } ],
  [ "addons", "accounting_integration", "Accounting integration", false, true,
    { "core"=>:addon, "plus"=>:addon, "enterprise"=>:addon } ],
  [ "addons", "per_pax_booking", "Per pax booking", false, true,
    { "enterprise"=>:addon } ]
].freeze

ActiveRecord::Base.transaction do
  plans = plan_defs.to_h do |d|
    plan = Plan.find_or_initialize_by(slug: d[:slug])
    plan.update!(name: d[:name], position: d[:position], most_popular: d[:most_popular], active: true)
    [ d[:slug], plan ]
  end

  groups = group_defs.to_h do |slug, (name, pos)|
    g = FeatureGroup.find_or_initialize_by(slug: slug)
    g.update!(name: name, position: pos)
    [ slug, g ]
  end

  plan_feature_defs.each_with_index do |(group_slug, slug, name, leveled, addon, cells), idx|
    feature = Feature.find_or_initialize_by(slug: slug)
    feature.update!(feature_group: groups.fetch(group_slug), name: name,
                    position: idx, leveled: leveled, addon: addon)

    cells.each do |plan_slug, cell|
      pf = PlanFeature.find_or_initialize_by(plan: plans.fetch(plan_slug), feature: feature)
      enabled  = cell != :addon && cell != false && !cell.nil?
      level    = cell.is_a?(String) ? cell : nil
      is_addon = cell == :addon
      pf.update!(enabled: enabled, level: level, addon: is_addon)
    end
  end
end

puts "Seeded #{Plan.count} plans, #{Feature.count} features, #{PlanFeature.count} plan_features." unless Rails.env.test?
