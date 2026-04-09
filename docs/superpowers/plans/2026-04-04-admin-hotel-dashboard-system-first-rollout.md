# Admin + Hotel Dashboard System First Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define the first shared Preline-based dashboard primitives and refactor the admin and hotel dashboard home pages to use them.

**Architecture:** Keep the current Rails + ERB + Tailwind + Preline dashboard foundation, but move the dashboard home pages away from page-local card/panel markup and onto a shared partial system. The first rollout stays intentionally narrow: shared dashboard primitives plus the two dashboard index pages, creating the pattern that later subpage migrations will follow.

**Tech Stack:** Rails 8, ERB, Tailwind (`tailwindcss-rails`), Preline, Importmap, Turbo, Stimulus, RSpec/Capybara

---

## File map

### Existing files to modify
- `app/views/admin/dashboard/index.html.erb` — replace inline admin dashboard panels with shared primitives
- `app/views/hotel_portal/dashboard/index.html.erb` — replace inline hotel dashboard panels with shared primitives
- `app/assets/tailwind/application.css` — extend shared dashboard utility classes only if the primitives need a small common styling hook
- `spec/system/admin/layout_shell_spec.rb` — extend admin coverage to ensure the new dashboard primitives still render the core admin dashboard content
- `spec/system/hotel/layout_shell_spec.rb` — extend hotel shell coverage to ensure the hotel dashboard still renders the shared dashboard sections correctly
- `spec/system/hotel/onboarding_flow_spec.rb` — verify the hotel dashboard rollout does not break the locked onboarding/pending-review state

### New shared partials to create
- `app/views/shared/dashboard/_page_header.html.erb` — reusable page header with title, optional breadcrumb slot, and optional actions slot
- `app/views/shared/dashboard/_stat_card.html.erb` — reusable KPI/stat card
- `app/views/shared/dashboard/_panel.html.erb` — reusable content panel with header/body/action areas
- `app/views/shared/dashboard/_empty_state.html.erb` — reusable empty-state block used inside panels
- `app/views/shared/dashboard/_badge.html.erb` — reusable dashboard badge/status primitive for dashboard page usage

### New specs to create
- `spec/system/admin/dashboard_page_spec.rb` — verifies the admin dashboard home page still renders key dashboard sections after the primitive refactor
- `spec/system/hotel/dashboard_page_spec.rb` — verifies the hotel dashboard home page still renders key dashboard sections after the primitive refactor

## Task 1: Create admin dashboard page coverage

**Files:**
- Create: `spec/system/admin/dashboard_page_spec.rb`
- Test existing login flow against: `app/views/admin/dashboard/index.html.erb`

- [ ] **Step 1: Write the failing admin dashboard page spec**

```ruby
require "rails_helper"

RSpec.describe "Admin dashboard page", type: :system do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    driven_by(:rack_test)

    visit login_path
    fill_in "Email address", with: superadmin.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
  end

  it "renders the admin dashboard sections" do
    visit admin_dashboard_path

    expect(page).to have_content("Operational Control Center")
    expect(page).to have_content("Hotels Pending Review")
    expect(page).to have_content("Failed Webhooks")
    expect(page).to have_content("Recent Confirmed Bookings")
    expect(page).to have_link("View analytics", href: admin_analytics_path)
  end
end
```

- [ ] **Step 2: Run the admin dashboard page spec to verify it fails**

Run: `bundle exec rspec spec/system/admin/dashboard_page_spec.rb`
Expected: FAIL with `LoadError` or missing file because `spec/system/admin/dashboard_page_spec.rb` does not exist yet.

- [ ] **Step 3: Create the admin dashboard page spec file**

```ruby
require "rails_helper"

RSpec.describe "Admin dashboard page", type: :system do
  let(:superadmin) { create(:user, :superadmin) }

  before do
    driven_by(:rack_test)

    visit login_path
    fill_in "Email address", with: superadmin.email
    fill_in "Password", with: "password123"
    click_button "Sign In"
  end

  it "renders the admin dashboard sections" do
    visit admin_dashboard_path

    expect(page).to have_content("Operational Control Center")
    expect(page).to have_content("Hotels Pending Review")
    expect(page).to have_content("Failed Webhooks")
    expect(page).to have_content("Recent Confirmed Bookings")
    expect(page).to have_link("View analytics", href: admin_analytics_path)
  end
end
```

- [ ] **Step 4: Run the admin dashboard page spec to capture the baseline**

Run: `bundle exec rspec spec/system/admin/dashboard_page_spec.rb`
Expected: PASS on the current dashboard content before the primitive refactor begins.

- [ ] **Step 5: Commit**

```bash
git add spec/system/admin/dashboard_page_spec.rb
git commit -m "test: add admin dashboard page coverage"
```

## Task 2: Create hotel dashboard page coverage

**Files:**
- Create: `spec/system/hotel/dashboard_page_spec.rb`
- Test existing dashboard behavior against: `app/views/hotel_portal/dashboard/index.html.erb`
- Test existing locked state against: `spec/system/hotel/onboarding_flow_spec.rb`

- [ ] **Step 1: Write the failing hotel dashboard page spec**

```ruby
require "rails_helper"

RSpec.describe "Hotel dashboard page", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
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

  it "renders the hotel dashboard sections" do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_content("Dashboard")
    expect(page).to have_content("Arrival Board")
    expect(page).to have_content("Pending Actions")
    expect(page).to have_content("7-Day Occupancy")
    expect(page).to have_content("Recent Bookings")
    expect(page).to have_link("View all bookings", href: hotel_bookings_path(hotel))
  end
end
```

- [ ] **Step 2: Run the hotel dashboard page spec to verify it fails**

Run: `bundle exec rspec spec/system/hotel/dashboard_page_spec.rb`
Expected: FAIL with `LoadError` or missing file because `spec/system/hotel/dashboard_page_spec.rb` does not exist yet.

- [ ] **Step 3: Create the hotel dashboard page spec file**

```ruby
require "rails_helper"

RSpec.describe "Hotel dashboard page", type: :system do
  let(:account) { create(:account) }
  let(:hotel) { create(:hotel, account: account, status: "approved") }
  let(:user) { create(:user, account: account, role: "admin") }
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

  it "renders the hotel dashboard sections" do
    visit hotel_dashboard_path(hotel)

    expect(page).to have_content("Dashboard")
    expect(page).to have_content("Arrival Board")
    expect(page).to have_content("Pending Actions")
    expect(page).to have_content("7-Day Occupancy")
    expect(page).to have_content("Recent Bookings")
    expect(page).to have_link("View all bookings", href: hotel_bookings_path(hotel))
  end
end
```

- [ ] **Step 4: Run the hotel dashboard page spec and locked-state spec to capture the baseline**

Run: `bundle exec rspec spec/system/hotel/dashboard_page_spec.rb spec/system/hotel/onboarding_flow_spec.rb`
Expected: PASS on current hotel dashboard behavior and locked onboarding behavior before the primitive refactor begins.

- [ ] **Step 5: Commit**

```bash
git add spec/system/hotel/dashboard_page_spec.rb spec/system/hotel/onboarding_flow_spec.rb
git commit -m "test: add hotel dashboard page coverage"
```

## Task 3: Create shared dashboard primitives

**Files:**
- Create: `app/views/shared/dashboard/_page_header.html.erb`
- Create: `app/views/shared/dashboard/_stat_card.html.erb`
- Create: `app/views/shared/dashboard/_panel.html.erb`
- Create: `app/views/shared/dashboard/_empty_state.html.erb`
- Create: `app/views/shared/dashboard/_badge.html.erb`
- Modify (only if needed): `app/assets/tailwind/application.css`
- Test: `spec/system/admin/dashboard_page_spec.rb`
- Test: `spec/system/hotel/dashboard_page_spec.rb`

- [ ] **Step 1: Create the shared page header primitive**

Create `app/views/shared/dashboard/_page_header.html.erb`:

```erb
<div class="flex flex-col gap-y-4 md:flex-row md:items-center md:justify-between">
  <div>
    <% if local_assigns[:breadcrumb].present? %>
      <div class="mb-2">
        <%= breadcrumb %>
      </div>
    <% end %>

    <h1 class="text-2xl font-bold text-neutral-text-primary"><%= title %></h1>

    <% if local_assigns[:subtitle].present? %>
      <p class="mt-1 text-sm text-neutral-text-secondary"><%= subtitle %></p>
    <% end %>
  </div>

  <% if local_assigns[:actions].present? %>
    <div class="inline-flex gap-x-2">
      <%= actions %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Create the shared stat card primitive**

Create `app/views/shared/dashboard/_stat_card.html.erb`:

```erb
<div class="card p-4 md:p-5 space-y-3">
  <div class="flex items-start justify-between gap-3">
    <div>
      <p class="text-xs uppercase tracking-wider text-neutral-text-secondary font-semibold"><%= label %></p>
      <% if local_assigns[:subtext].present? %>
        <p class="mt-1 text-xs text-neutral-text-secondary"><%= subtext %></p>
      <% end %>
    </div>

    <% if local_assigns[:action].present? %>
      <%= action %>
    <% end %>
  </div>

  <% if local_assigns[:body].present? %>
    <%= body %>
  <% else %>
    <p class="text-2xl font-bold text-neutral-text-primary"><%= value %></p>
  <% end %>
</div>
```

- [ ] **Step 3: Create the shared panel primitive**

Create `app/views/shared/dashboard/_panel.html.erb`:

```erb
<div class="card <%= local_assigns[:panel_classes] %>">
  <% if local_assigns[:title].present? || local_assigns[:action].present? %>
    <div class="p-4 md:p-5 border-b border-neutral-border flex items-center justify-between gap-3">
      <div>
        <% if local_assigns[:eyebrow].present? %>
          <p class="text-xs uppercase tracking-wider text-neutral-text-secondary font-semibold"><%= eyebrow %></p>
        <% end %>
        <% if local_assigns[:title].present? %>
          <h2 class="text-lg font-bold text-neutral-text-primary"><%= title %></h2>
        <% end %>
      </div>

      <% if local_assigns[:action].present? %>
        <%= action %>
      <% end %>
    </div>
  <% end %>

  <div class="p-4 md:p-5 <%= local_assigns[:body_classes] %>">
    <%= body %>
  </div>
</div>
```

- [ ] **Step 4: Create the shared empty-state primitive**

Create `app/views/shared/dashboard/_empty_state.html.erb`:

```erb
<div class="py-10 text-center">
  <% if local_assigns[:title].present? %>
    <h3 class="text-sm font-semibold text-neutral-text-primary"><%= title %></h3>
  <% end %>

  <p class="text-sm text-neutral-text-secondary <%= local_assigns[:title].present? ? 'mt-1' : '' %>"><%= message %></p>

  <% if local_assigns[:action].present? %>
    <div class="mt-4">
      <%= action %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 5: Create the shared badge primitive**

Create `app/views/shared/dashboard/_badge.html.erb`:

```erb
<%
  tone_classes = case tone
                 when "success"
                   "badge badge-success"
                 when "warning"
                   "badge badge-warning"
                 when "error"
                   "badge badge-error"
                 else
                   "badge badge-neutral"
                 end
%>

<span class="<%= tone_classes %>"><%= label %></span>
```

- [ ] **Step 6: Run the new dashboard page specs before using the primitives**

Run: `bundle exec rspec spec/system/admin/dashboard_page_spec.rb spec/system/hotel/dashboard_page_spec.rb`
Expected: PASS on the current dashboard pages before refactoring them to the shared primitives.

- [ ] **Step 7: Commit**

```bash
git add app/views/shared/dashboard/_page_header.html.erb app/views/shared/dashboard/_stat_card.html.erb app/views/shared/dashboard/_panel.html.erb app/views/shared/dashboard/_empty_state.html.erb app/views/shared/dashboard/_badge.html.erb app/assets/tailwind/application.css spec/system/admin/dashboard_page_spec.rb spec/system/hotel/dashboard_page_spec.rb
git commit -m "feat: add shared dashboard primitives"
```

## Task 4: Refactor the admin dashboard page to use shared primitives

**Files:**
- Modify: `app/views/admin/dashboard/index.html.erb`
- Test: `spec/system/admin/dashboard_page_spec.rb`
- Test existing shell: `spec/system/admin/layout_shell_spec.rb`

- [ ] **Step 1: Replace the admin dashboard page header with the shared header primitive**

Use this render near the top of `app/views/admin/dashboard/index.html.erb`:

```erb
<%= render "shared/dashboard/page_header",
  title: "Operational Control Center",
  breadcrumb: capture do %>
    <nav class="flex" aria-label="Breadcrumb">
      <ol class="flex items-center whitespace-nowrap min-w-0">
        <li class="flex items-center text-sm text-neutral-text-secondary">
          Superadmin
          <svg class="flex-shrink-0 mx-2 overflow-visible h-4 w-4 text-gray-400" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>
        </li>
        <li class="text-sm font-semibold text-brand-primary truncate" aria-current="page">
          Dashboard
        </li>
      </ol>
    </nav>
  <% end %>
```

- [ ] **Step 2: Replace the KPI row with shared stat card renders**

Refactor the KPI row to render `shared/dashboard/stat_card` twice, using `body:` blocks for the inner two-column stat sections:

```erb
<%= render "shared/dashboard/stat_card",
  label: "Revenue & Margin (MTD)",
  action: link_to("View analytics", admin_analytics_path, class: "text-sm font-medium text-brand-primary hover:underline"),
  body: capture do %>
    <div class="grid grid-cols-2 gap-3">
      <div class="p-3 bg-neutral-bg rounded-2xl">
        <p class="text-[10px] uppercase text-neutral-text-secondary tracking-wider">Revenue</p>
        <p class="text-xl font-bold text-neutral-text-primary mt-1">RM <%= number_with_precision(@revenue_this_month, precision: 2) %></p>
      </div>
      <div class="p-3 bg-neutral-bg rounded-2xl">
        <p class="text-[10px] uppercase text-neutral-text-secondary tracking-wider">Margin</p>
        <p class="text-xl font-bold text-neutral-text-primary mt-1">RM <%= number_with_precision(@margin_this_month, precision: 2) %></p>
      </div>
    </div>
  <% end %>
```

and similarly for the bookings/hotels stat card.

- [ ] **Step 3: Replace each major admin dashboard section with the shared panel primitive**

Use `shared/dashboard/panel` for:
- Hotels Pending Review
- Failed Webhooks
- Recent Confirmed Bookings

For each empty state, replace inline empty markup with:

```erb
<%= render "shared/dashboard/empty_state", message: "No hotels currently pending review." %>
```

or the section-appropriate equivalent message.

- [ ] **Step 4: Run the admin dashboard page and shell specs**

Run: `bundle exec rspec spec/system/admin/dashboard_page_spec.rb spec/system/admin/layout_shell_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/admin/dashboard/index.html.erb spec/system/admin/dashboard_page_spec.rb spec/system/admin/layout_shell_spec.rb
 git commit -m "refactor: move admin dashboard to shared primitives"
```

## Task 5: Refactor the hotel dashboard page to use shared primitives

**Files:**
- Modify: `app/views/hotel_portal/dashboard/index.html.erb`
- Test: `spec/system/hotel/dashboard_page_spec.rb`
- Test existing shell: `spec/system/hotel/layout_shell_spec.rb`
- Test existing locked flow: `spec/system/hotel/onboarding_flow_spec.rb`

- [ ] **Step 1: Replace the hotel dashboard header with the shared header primitive**

Use this render near the top of `app/views/hotel_portal/dashboard/index.html.erb`:

```erb
<%= render "shared/dashboard/page_header",
  title: "#{@current_hotel.name} Dashboard",
  breadcrumb: capture do %>
    <nav class="flex" aria-label="Breadcrumb">
      <ol class="flex items-center whitespace-nowrap min-w-0">
        <li class="flex items-center text-sm text-neutral-text-secondary">
          Hotel Admin
          <svg class="flex-shrink-0 mx-2 overflow-visible h-4 w-4 text-gray-400" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 18 6-6-6-6"/></svg>
        </li>
        <li class="text-sm font-semibold text-brand-primary truncate" aria-current="page">
          Dashboard
        </li>
      </ol>
    </nav>
  <% end %>,
  actions: capture do %>
    <a class="btn btn-secondary" href="<%= help_center_path %>">
      <svg class="w-4 h-4 me-2" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>
      Help Center
    </a>
  <% end %>
```

- [ ] **Step 2: Replace the arrival/pending/occupancy/recent-bookings sections with shared panel renders**

Refactor these sections to use `shared/dashboard/panel`:
- Arrival Board
- Pending Actions
- 7-Day Occupancy
- Recent Bookings

For status labels inside the dashboard, replace inline badge spans with `shared/dashboard/badge` renders such as:

```erb
<%= render "shared/dashboard/badge", tone: "success", label: "Pre-checked" %>
```

and

```erb
<%= render "shared/dashboard/badge", tone: "warning", label: "Pending" %>
```

- [ ] **Step 3: Replace dashboard empty blocks with the shared empty-state primitive**

Use `shared/dashboard/empty_state` for messages such as:
- `No arrivals today.`
- `No arrivals tomorrow.`
- `No bookings found.`

- [ ] **Step 4: Run hotel dashboard and shell verification**

Run: `bundle exec rspec spec/system/hotel/dashboard_page_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/views/hotel_portal/dashboard/index.html.erb spec/system/hotel/dashboard_page_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb
git commit -m "refactor: move hotel dashboard to shared primitives"
```

## Task 6: Final verification for the first rollout slice

**Files:**
- Test: `spec/system/admin/dashboard_page_spec.rb`
- Test: `spec/system/hotel/dashboard_page_spec.rb`
- Test: `spec/system/admin/layout_shell_spec.rb`
- Test: `spec/system/hotel/layout_shell_spec.rb`
- Test: `spec/system/hotel/onboarding_flow_spec.rb`
- Inspect: `app/views/admin/dashboard/index.html.erb`
- Inspect: `app/views/hotel_portal/dashboard/index.html.erb`
- Inspect: `app/views/shared/dashboard/**`

- [ ] **Step 1: Run the focused dashboard verification suite**

Run: `bundle exec rspec spec/system/admin/dashboard_page_spec.rb spec/system/hotel/dashboard_page_spec.rb spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb`
Expected: PASS.

- [ ] **Step 2: Review the two dashboard pages for primitive usage**

Open these files and confirm the main sections now render shared dashboard primitives rather than large page-local wrappers:

```text
app/views/admin/dashboard/index.html.erb
app/views/hotel_portal/dashboard/index.html.erb
```

Expected:
- shared page header used in both
- shared panel used for major sections in both
- shared empty-state used where applicable
- shared badge used for dashboard status labels
- shared stat card used for admin KPI sections

- [ ] **Step 3: Review the working tree for rollout scope**

Run: `git diff -- app/views/admin/dashboard/index.html.erb app/views/hotel_portal/dashboard/index.html.erb app/views/shared/dashboard app/assets/tailwind/application.css spec/system/admin/dashboard_page_spec.rb spec/system/hotel/dashboard_page_spec.rb spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb`
Expected: diff only shows the planned shared dashboard primitive work and the two dashboard page refactors.

- [ ] **Step 4: Commit**

```bash
git add app/views/admin/dashboard/index.html.erb app/views/hotel_portal/dashboard/index.html.erb app/views/shared/dashboard app/assets/tailwind/application.css spec/system/admin/dashboard_page_spec.rb spec/system/hotel/dashboard_page_spec.rb spec/system/admin/layout_shell_spec.rb spec/system/hotel/layout_shell_spec.rb spec/system/hotel/onboarding_flow_spec.rb
git commit -m "refactor: add shared dashboard system rollout"
```