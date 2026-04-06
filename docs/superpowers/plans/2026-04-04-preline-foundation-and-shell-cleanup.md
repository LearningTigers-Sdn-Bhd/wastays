# Preline Foundation and Shell Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize Preline as the shared UI foundation for WAStays and extract the first shared shell primitives for the admin and hotel dashboard surfaces.

**Architecture:** Keep the existing Rails + ERB + Tailwind + Importmap stack, but make Preline the clear owner for generic UI interactions on dashboard surfaces. The first pass stays intentionally narrow: standardize Preline loading, move repeated shell markup into shared partials, and preserve current behavior while making admin and hotel layouts structurally cleaner.

**Tech Stack:** Rails 8, ERB, Tailwind (`tailwindcss-rails`), Importmap, Turbo, Stimulus, Preline, RSpec/Capybara

---

## File map

### Existing files to modify
- `config/importmap.rb` — confirm and standardize how Preline is pinned
- `app/javascript/application.js` — make Preline initialization explicit and consistent
- `app/views/layouts/admin.html.erb` — switch repeated shell pieces to shared partials and align Preline setup
- `app/views/layouts/hotel.html.erb` — switch repeated shell pieces to shared partials and align Preline setup
- `app/views/layouts/application.html.erb` — prepare public layout for consistent Preline asset loading without redesigning public pages yet
- `app/views/shared/_toast.html.erb` — keep toast rendering compatible with the new shared feedback wrapper
- `spec/system/hotel/onboarding_flow_spec.rb` — verify the locked hotel shell still behaves correctly

### New shared partials to create
- `app/views/shared/navigation/_admin_profile_dropdown.html.erb` — reusable admin topbar profile dropdown
- `app/views/shared/navigation/_hotel_profile_dropdown.html.erb` — reusable hotel topbar profile dropdown
- `app/views/shared/navigation/_admin_sidebar.html.erb` — reusable admin sidebar
- `app/views/shared/navigation/_hotel_sidebar.html.erb` — reusable hotel sidebar
- `app/views/shared/navigation/_admin_mobile_nav.html.erb` — reusable admin mobile bottom nav
- `app/views/shared/navigation/_hotel_mobile_nav.html.erb` — reusable hotel mobile bottom nav
- `app/views/shared/feedback/_flash_toasts.html.erb` — reusable toast container for layouts

### New specs to create
- `spec/system/admin/layout_shell_spec.rb` — verify the admin shell still renders key navigation and shared UI correctly after extraction
- `spec/system/hotel/layout_shell_spec.rb` — verify the hotel shell still renders key navigation/toasts correctly and preserves the locked-shell behavior boundaries

## Task 1: Stabilize Preline asset loading

**Files:**
- Modify: `config/importmap.rb`
- Modify: `app/javascript/application.js`
- Modify: `app/views/layouts/admin.html.erb`
- Modify: `app/views/layouts/hotel.html.erb`
- Modify: `app/views/layouts/application.html.erb`
- Test: `spec/system/admin/layout_shell_spec.rb`

- [ ] **Step 1: Write the failing admin shell spec**

```ruby
require "rails_helper"

RSpec.describe "Admin layout shell", type: :system do
  let(:superadmin) { create(:user, :superadmin, email: "admin-shell@example.com") }

  before do
    driven_by(:rack_test)

    visit login_path
    fill_in "Email address", with: superadmin.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
  end

  it "renders the shared admin shell navigation" do
    visit admin_dashboard_path

    expect(page).to have_content("Superadmin Control Panel")
    expect(page).to have_link("Dashboard", href: admin_dashboard_path)
    expect(page).to have_link("Hotels", href: admin_hotels_path)
    expect(page).to have_link("Bookings", href: admin_bookings_path)
    expect(page).to have_link("Reconciliation", href: admin_reconciliation_dashboard_path)
    expect(page).to have_link("My Profile", href: edit_admin_profile_path)
  end
end
```

- [ ] **Step 2: Run the admin shell spec to verify it fails**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb`
Expected: FAIL with `LoadError` or missing file because `spec/system/admin/layout_shell_spec.rb` does not exist yet.

- [ ] **Step 3: Create the admin shell spec file**

```ruby
require "rails_helper"

RSpec.describe "Admin layout shell", type: :system do
  let(:superadmin) { create(:user, :superadmin, email: "admin-shell@example.com") }

  before do
    driven_by(:rack_test)

    visit login_path
    fill_in "Email address", with: superadmin.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
  end

  it "renders the shared admin shell navigation" do
    visit admin_dashboard_path

    expect(page).to have_content("Superadmin Control Panel")
    expect(page).to have_link("Dashboard", href: admin_dashboard_path)
    expect(page).to have_link("Hotels", href: admin_hotels_path)
    expect(page).to have_link("Bookings", href: admin_bookings_path)
    expect(page).to have_link("Reconciliation", href: admin_reconciliation_dashboard_path)
    expect(page).to have_link("My Profile", href: edit_admin_profile_path)
  end
end
```

- [ ] **Step 4: Run the admin shell spec to capture the current baseline**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb`
Expected: PASS on current behavior before the extraction starts.

- [ ] **Step 5: Update Preline loading to be explicit and consistent**

Update `config/importmap.rb` so the Preline pin remains explicit:

```ruby
pin "application"
pin "turbo_confirm"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "preline", to: "https://cdn.jsdelivr.net/npm/preline@2.4.1/dist/preline.min.js"
pin_all_from "app/javascript/controllers", under: "controllers"
```

Update `app/javascript/application.js` so Preline initialization is isolated and explicit:

```javascript
import "@hotwired/turbo-rails"
import "controllers"
import "turbo_confirm"

const initializePreline = async () => {
  try {
    await import("preline")

    if (typeof window.HSStaticMethods !== "undefined") {
      window.HSStaticMethods.autoInit()
    }
  } catch (error) {
    console.warn("Preline failed to initialize", error)
  }
}

document.addEventListener("turbo:load", initializePreline)
```

Update the layout heads so all three layouts load the same Preline stylesheet before `javascript_importmap_tags`:

```erb
<%= stylesheet_link_tag :app, "data-turbo-track": (Rails.env.production? ? "reload" : nil) %>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/preline@2.4.1/dist/preline.min.css">
<%= javascript_importmap_tags %>
```

- [ ] **Step 6: Run the admin shell spec to verify the foundation still works**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/importmap.rb app/javascript/application.js app/views/layouts/admin.html.erb app/views/layouts/hotel.html.erb app/views/layouts/application.html.erb spec/system/admin/layout_shell_spec.rb
git commit -m "refactor: standardize preline layout loading"
```

## Task 2: Extract shared feedback and profile dropdown partials

**Files:**
- Create: `app/views/shared/feedback/_flash_toasts.html.erb`
- Create: `app/views/shared/navigation/_admin_profile_dropdown.html.erb`
- Create: `app/views/shared/navigation/_hotel_profile_dropdown.html.erb`
- Modify: `app/views/layouts/admin.html.erb`
- Modify: `app/views/layouts/hotel.html.erb`
- Modify: `app/views/shared/_toast.html.erb`
- Test: `spec/system/admin/layout_shell_spec.rb`
- Test: `spec/system/hotel/layout_shell_spec.rb`

- [ ] **Step 1: Write the failing hotel shell spec**

```ruby
require "rails_helper"

RSpec.describe "Hotel layout shell", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin", email: "hotel-shell@example.com") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    driven_by(:rack_test)

    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_hotel_profile"))
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
  end

  it "renders the hotel shell navigation and shared toast container" do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_link("Dashboard", href: hotel_dashboard_path(hotel))
    expect(page).to have_link("Arrivals", href: hotel_arrivals_path(hotel))
    expect(page).to have_link("Bookings", href: hotel_bookings_path(hotel))
    expect(page).to have_link("Settings", href: hotel_settings_path(hotel))
    expect(page).to have_css("#flash_toasts")
    expect(page).to have_link("My Profile", href: edit_hotel_user_profile_path(hotel))
  end
end
```

- [ ] **Step 2: Run the hotel shell spec to verify it fails**

Run: `bundle exec rspec spec/system/hotel/layout_shell_spec.rb`
Expected: FAIL with `LoadError` or missing file because `spec/system/hotel/layout_shell_spec.rb` does not exist yet.

- [ ] **Step 3: Create the hotel shell spec file**

```ruby
require "rails_helper"

RSpec.describe "Hotel layout shell", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin", email: "hotel-shell@example.com") }
  let(:role) { create(:role, account: account, slug: "hotel_owner", name: "Hotel Owner") }

  before do
    driven_by(:rack_test)

    Permission.find_or_create_by!(slug: "manage_hotel_profile") { |permission| permission.name = "Manage Hotel Profile" }
    RolePermission.find_or_create_by!(role: role, permission: Permission.find_by!(slug: "manage_hotel_profile"))
    UserRole.find_or_create_by!(user: user, role: role)
    UserHotelAccess.find_or_create_by!(user: user, hotel: hotel, role: role)

    visit login_path
    fill_in "Email address", with: user.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
  end

  it "renders the hotel shell navigation and shared toast container" do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_link("Dashboard", href: hotel_dashboard_path(hotel))
    expect(page).to have_link("Arrivals", href: hotel_arrivals_path(hotel))
    expect(page).to have_link("Bookings", href: hotel_bookings_path(hotel))
    expect(page).to have_link("Settings", href: hotel_settings_path(hotel))
    expect(page).to have_css("#flash_toasts")
    expect(page).to have_link("My Profile", href: edit_hotel_user_profile_path(hotel))
  end
end
```

- [ ] **Step 4: Run both shell specs to capture the baseline**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb`
Expected: PASS on current behavior before extraction.

- [ ] **Step 5: Create the shared feedback wrapper partial**

Create `app/views/shared/feedback/_flash_toasts.html.erb`:

```erb
<div id="flash_toasts" class="fixed top-4 right-4 z-[120] flex flex-col gap-2 pointer-events-none">
  <% flash.each do |key, value| %>
    <%= render "shared/toast", key: key, value: value %>
  <% end %>
</div>
```

- [ ] **Step 6: Create the shared admin profile dropdown partial**

Create `app/views/shared/navigation/_admin_profile_dropdown.html.erb`:

```erb
<div class="relative inline-flex" data-controller="dropdown">
  <button id="admin-profile-toggle" type="button" class="w-10 h-10 inline-flex justify-center items-center gap-x-2 text-sm font-semibold rounded-full border border-transparent text-neutral-text-secondary hover:bg-neutral-bg focus:outline-none focus:bg-neutral-bg disabled:opacity-50 disabled:pointer-events-none" data-action="click->dropdown#toggle">
    <span class="inline-block h-10 w-10 rounded-full ring-2 ring-white bg-gray-100 overflow-hidden">
      <svg class="h-full w-full text-gray-300" fill="currentColor" viewBox="0 0 24 24">
        <path d="M24 20.993V24H0v-2.996A14.977 14.977 0 0112.004 15c4.904 0 9.26 2.354 11.996 5.993zM16.002 8.999a4 4 0 11-8 0 4 4 0 018 0z" />
      </svg>
    </span>
  </button>

  <div class="absolute right-0 top-full mt-2 w-60 bg-white shadow-xl rounded-xl p-2 hidden z-[100] border border-neutral-border animate-in fade-in zoom-in duration-200" data-dropdown-target="menu">
    <div class="py-3 px-4 -m-2 bg-neutral-bg rounded-t-xl mb-2 border-b border-neutral-border">
      <p class="text-xs text-neutral-text-secondary">Signed in as</p>
      <p class="text-sm font-semibold text-neutral-text-primary truncate"><%= current_user.email %></p>
    </div>
    <div class="space-y-1">
      <a class="flex items-center gap-x-3.5 py-2 px-3 rounded-lg text-sm text-neutral-text-primary hover:bg-neutral-bg focus:ring-2 focus:ring-brand-primary" href="<%= edit_admin_profile_path %>">
        <svg class="flex-shrink-0 w-4 h-4" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
        My Profile
      </a>
      <div class="border-t border-neutral-border my-1"></div>
      <%= button_to logout_path, method: :delete, class: "flex items-center gap-x-3.5 py-2 px-3 rounded-lg text-sm text-status-error hover:bg-red-50 focus:ring-2 focus:ring-status-error w-full text-left" do %>
        <svg class="flex-shrink-0 w-4 h-4" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
        Logout
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 7: Create the shared hotel profile dropdown partial**

Create `app/views/shared/navigation/_hotel_profile_dropdown.html.erb`:

```erb
<div class="relative inline-flex" data-controller="dropdown">
  <button data-action="click->dropdown#toggle" type="button" class="w-[2.375rem] h-[2.375rem] inline-flex justify-center items-center gap-x-2 text-sm font-semibold rounded-full border border-transparent text-neutral-text-secondary hover:bg-neutral-bg focus:outline-none focus:bg-neutral-bg disabled:opacity-50 disabled:pointer-events-none">
    <span class="inline-block h-[2.375rem] w-[2.375rem] rounded-full ring-2 ring-white bg-gray-100 overflow-hidden">
      <svg class="h-full w-full text-gray-300" fill="currentColor" viewBox="0 0 24 24">
        <path d="M24 20.993V24H0v-2.996A14.977 14.977 0 0112.004 15c4.904 0 9.26 2.354 11.996 5.993zM16.002 8.999a4 4 0 11-8 0 4 4 0 018 0z" />
      </svg>
    </span>
  </button>

  <div data-dropdown-target="menu" class="hidden absolute right-0 top-full min-w-[15rem] bg-white shadow-xl rounded-lg p-2 mt-2 z-[100] border border-neutral-border animate-in fade-in zoom-in duration-200">
    <div class="py-3 px-5 -m-2 bg-gray-100 rounded-t-lg">
      <p class="text-sm text-gray-500">Signed in as</p>
      <p class="text-sm font-medium text-gray-800"><%= current_user.email %></p>
    </div>
    <div class="mt-2 py-2 first:pt-0 last:pb-0">
      <a class="flex items-center gap-x-3.5 py-2 px-3 rounded-lg text-sm text-gray-800 hover:bg-gray-100 focus:ring-2 focus:ring-blue-500" href="<%= edit_hotel_user_profile_path(current_hotel) %>">
        <svg class="flex-shrink-0 w-4 h-4" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
        My Profile
      </a>
      <%= button_to logout_path, method: :delete, class: "flex items-center gap-x-3.5 py-2 px-3 rounded-lg text-sm text-gray-800 hover:bg-gray-100 focus:ring-2 focus:ring-blue-500 w-full text-left" do %>
        <svg class="flex-shrink-0 w-4 h-4" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>
        Logout
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 8: Keep the toast partial compatible with the shared wrapper**

Set `app/views/shared/_toast.html.erb` to:

```erb
<div data-controller="toast" class="pointer-events-auto min-w-[260px] max-w-sm rounded-xl border shadow-lg px-4 py-3 transition-all duration-300 bg-white <%= key == 'alert' ? 'border-red-200' : 'border-green-200' %>">
  <div class="flex items-start gap-3">
    <div class="<%= key == 'alert' ? 'text-red-600' : 'text-green-600' %>">
      <svg class="w-5 h-5" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
        <% if key == 'alert' %>
          <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v4m0 4h.01M4.93 19h14.14c1.54 0 2.5-1.67 1.73-3L13.73 4c-.77-1.33-2.69-1.33-3.46 0L3.2 16c-.77 1.33.19 3 1.73 3z" />
        <% else %>
          <path stroke-linecap="round" stroke-linejoin="round" d="m9 12.75 2.25 2.25L15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
        <% end %>
      </svg>
    </div>
    <div class="flex-1 text-sm text-gray-800"><%= value %></div>
  </div>
</div>
```

- [ ] **Step 9: Render the shared feedback/profile partials from the layouts**

Update the admin layout so the inline dropdown and inline flash wrapper are replaced with:

```erb
<%= render "shared/navigation/admin_profile_dropdown" %>
```

and later in the body:

```erb
<%= render "shared/feedback/flash_toasts", flash: flash %>
```

Update the hotel layout so the inline dropdown and inline flash wrapper are replaced with:

```erb
<%= render "shared/navigation/hotel_profile_dropdown" %>
```

and later in the body:

```erb
<%= render "shared/feedback/flash_toasts", flash: flash %>
```

- [ ] **Step 10: Run the shell specs plus locked-shell regression**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb`
Expected: PASS.

- [ ] **Step 11: Commit**

```bash
git add app/views/shared/feedback/_flash_toasts.html.erb app/views/shared/navigation/_admin_profile_dropdown.html.erb app/views/shared/navigation/_hotel_profile_dropdown.html.erb app/views/shared/_toast.html.erb app/views/layouts/admin.html.erb app/views/layouts/hotel.html.erb spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb
git commit -m "refactor: extract shared shell feedback and menus"
```

## Task 3: Extract shared sidebar and mobile navigation partials

**Files:**
- Create: `app/views/shared/navigation/_admin_sidebar.html.erb`
- Create: `app/views/shared/navigation/_hotel_sidebar.html.erb`
- Create: `app/views/shared/navigation/_admin_mobile_nav.html.erb`
- Create: `app/views/shared/navigation/_hotel_mobile_nav.html.erb`
- Modify: `app/views/layouts/admin.html.erb`
- Modify: `app/views/layouts/hotel.html.erb`
- Test: `spec/system/admin/layout_shell_spec.rb`
- Test: `spec/system/hotel/layout_shell_spec.rb`
- Test: `spec/system/hotel/onboarding_flow_spec.rb`

- [ ] **Step 1: Expand the admin shell spec to check sidebar and mobile labels**

Add these expectations inside `spec/system/admin/layout_shell_spec.rb`:

```ruby
expect(page).to have_link("Hotels", href: admin_hotels_path)
expect(page).to have_link("Bookings", href: admin_bookings_path)
expect(page).to have_link("Audit Logs", href: admin_audit_logs_path)
expect(page).to have_link("Help Guides", href: help_center_path)
expect(page).to have_text("Reconcile")
```

- [ ] **Step 2: Expand the hotel shell spec to check sidebar and mobile labels**

Add these expectations inside `spec/system/hotel/layout_shell_spec.rb`:

```ruby
expect(page).to have_link("Rates & Inventory", href: hotel_inventory_index_path(hotel))
expect(page).to have_link("Guests", href: hotel_guests_path(hotel))
expect(page).to have_link("Reports", href: hotel_reports_path(hotel))
expect(page).to have_text("Rooms")
```

- [ ] **Step 3: Run the shell specs to capture the baseline before extracting nav partials**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb`
Expected: PASS.

- [ ] **Step 4: Create the shared admin sidebar partial**

Move the current sidebar markup from `app/views/layouts/admin.html.erb` into `app/views/shared/navigation/_admin_sidebar.html.erb` unchanged.

The partial should start with:

```erb
<div id="application-sidebar" class="hs-overlay hs-overlay-open:translate-x-0 -translate-x-full transition-all duration-300 transform hidden fixed top-0 start-0 bottom-0 z-[80] w-64 bg-neutral-surface border-e border-neutral-border pt-7 pb-10 overflow-y-auto lg:block lg:translate-x-0 lg:end-auto lg:bottom-0 [&::-webkit-scrollbar]:w-2 [&::-webkit-scrollbar-thumb]:rounded-full [&::-webkit-scrollbar-thumb]:bg-neutral-border">
```

and preserve the current admin links and `controller_name`-based active states.

- [ ] **Step 5: Create the shared hotel sidebar partial**

Move the current sidebar markup from `app/views/layouts/hotel.html.erb` into `app/views/shared/navigation/_hotel_sidebar.html.erb` unchanged.

The partial should start with:

```erb
<div id="application-sidebar" class="hs-overlay hs-overlay-open:translate-x-0 -translate-x-full transition-all duration-300 transform hidden fixed top-0 start-0 bottom-0 z-[80] w-64 bg-neutral-surface border-e border-neutral-border pt-7 pb-10 overflow-y-auto lg:block lg:translate-x-0 lg:end-auto lg:bottom-0 [&::-webkit-scrollbar]:w-2 [&::-webkit-scrollbar-thumb]:rounded-full [&::-webkit-scrollbar-thumb]:bg-neutral-border">
```

and preserve the `locked_hotel_portal_shell?` guard from the layout.

- [ ] **Step 6: Create the shared admin mobile bottom nav partial**

Move the current admin mobile nav into `app/views/shared/navigation/_admin_mobile_nav.html.erb` unchanged.

The partial should start with:

```erb
<div class="sm:hidden fixed inset-x-0 bottom-0 z-40 border-t border-neutral-border bg-white shadow-lg pb-safe">
```

and preserve the current admin destinations.

- [ ] **Step 7: Create the shared hotel mobile bottom nav partial**

Move the current hotel mobile nav into `app/views/shared/navigation/_hotel_mobile_nav.html.erb` unchanged.

The partial should start with:

```erb
<div class="sm:hidden fixed inset-x-0 bottom-0 z-40 border-t border-neutral-border bg-white shadow-lg pb-safe">
```

and preserve the `current_page?` active state logic.

- [ ] **Step 8: Replace the inline nav markup in the layouts with renders**

Update `app/views/layouts/admin.html.erb` to render:

```erb
<%= render "shared/navigation/admin_sidebar" %>
<%= render "shared/navigation/admin_mobile_nav" %>
```

Update `app/views/layouts/hotel.html.erb` to render:

```erb
<%= render "shared/navigation/hotel_sidebar" %>
<%= render "shared/navigation/hotel_mobile_nav" %>
```

while preserving the existing `unless locked_hotel_portal_shell?` conditions around hotel-only nav.

- [ ] **Step 9: Run shell and locked-shell specs**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add app/views/shared/navigation/_admin_sidebar.html.erb app/views/shared/navigation/_hotel_sidebar.html.erb app/views/shared/navigation/_admin_mobile_nav.html.erb app/views/shared/navigation/_hotel_mobile_nav.html.erb app/views/layouts/admin.html.erb app/views/layouts/hotel.html.erb spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb
git commit -m "refactor: extract shared dashboard navigation shells"
```

## Task 4: Final verification for the foundation pass

**Files:**
- Test: `spec/system/admin/layout_shell_spec.rb`
- Test: `spec/system/hotel/layout_shell_spec.rb`
- Test: `spec/system/hotel/onboarding_flow_spec.rb`
- Test: `spec/system/hotel/settings_card_spec.rb`

- [ ] **Step 1: Run the focused shell and hotel settings specs**

Run: `bundle exec rspec spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb spec/system/hotel/settings_card_spec.rb`
Expected: PASS.

- [ ] **Step 2: Review the changed layouts for remaining duplicated shell blocks**

Open these files and confirm that the large inline blocks have been reduced to shared partial renders:

```text
app/views/layouts/admin.html.erb
app/views/layouts/hotel.html.erb
```

Expected: shared profile dropdown, shared toast wrapper, shared sidebar, and shared mobile nav are all rendered via partials.

- [ ] **Step 3: Review the working tree**

Run: `git diff -- app/views/layouts/admin.html.erb app/views/layouts/hotel.html.erb app/views/shared config/importmap.rb app/javascript/application.js spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb spec/system/hotel/settings_card_spec.rb`
Expected: diff only shows the planned Preline foundation and shell extraction changes.

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/admin.html.erb app/views/layouts/hotel.html.erb app/views/layouts/application.html.erb app/views/shared config/importmap.rb app/javascript/application.js spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb spec/system/hotel/settings_card_spec.rb
git commit -m "refactor: clean dashboard shell foundation"
```
