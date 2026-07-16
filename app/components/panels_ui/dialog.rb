# frozen_string_literal: true

module PanelsUI
  # Accessible modal dialog built on the native <dialog> element.
  #
  # The component renders *only* the dialog surface — it does NOT render a
  # trigger. Open it from anywhere with the native invoker-command attributes
  # (no JS wiring, no Stimulus scope coupling):
  #
  #   <button command="show-modal" commandfor="invite">Invite teammate</button>
  #
  #   <%= render PanelsUI::Dialog.new(
  #         id: "invite",
  #         title: "Invite teammate",
  #         description: "They'll get an email with a join link.") do |dialog| %>
  #     <% dialog.with_body   { render "invites/form" } %>
  #     <% dialog.with_footer do %>
  #       <button data-action="panels-ui--dialog#close">Cancel</button>
  #     <% end %>
  #   <% end %>
  #
  # `title` and `description` are plain strings rendered in the header and wired
  # to aria-labelledby / aria-describedby. `body` (the content region) and
  # `footer` are yielded slots. A visible `title` is preferred; `aria_label` is
  # available when the design intentionally has no visible heading.
  #
  # Using native <dialog> gives us focus trapping, Escape-to-close, the top layer,
  # and a stylable ::backdrop for free — the Stimulus controller only drives
  # scroll-lock, initial focus, and backdrop-click dismissal.
  class Dialog < PanelsUI::BaseComponent
    renders_one :body
    renders_one :footer

    SIZES = %i[sm md lg almost_full full].freeze

    # The <dialog> is the flex container so full-height variants fill and the body
    # region scrolls. sm/md/lg cap at 85vh; almost_full leaves a gap-6 (1.5rem)
    # frame; full goes edge-to-edge with no rounding.
    # `flex` must only apply while the dialog is open. An unconditional author
    # `display: flex` overrides the browser's `dialog:not([open]) { display: none }`
    # rule and leaks every closed dialog into normal document flow.
    style base: "fixed inset-0 m-auto hidden open:flex flex-col w-full overflow-hidden " \
                "bg-card text-card-foreground border border-border rounded-lg " \
                "shadow-lg p-0 z-modal backdrop:bg-black/50 backdrop:backdrop-blur-sm",
          variants: {
            size: {
              sm:          "max-w-sm max-h-[85vh]",
              md:          "max-w-md max-h-[85vh]",
              lg:          "max-w-lg max-h-[85vh]",
              almost_full: "max-w-none w-[calc(100vw-3rem)] h-[calc(100vh-3rem)] max-h-[calc(100vh-3rem)]",
              full:        "max-w-none w-screen h-screen max-h-none rounded-none border-0"
            }
          },
          defaults: { size: :md }

    def initialize(id:, title: nil, aria_label: nil, description: nil, size: :md, dismissible: true, class: nil)
      if title.blank? && aria_label.blank?
        raise ArgumentError, "Dialog requires a visible title or an aria_label"
      end

      @id          = id
      @title       = title
      @aria_label  = aria_label
      @description = description
      @size        = SIZES.include?(size) ? size : :md
      @dismissible = dismissible
      @class       = binding.local_variable_get(:class)
    end

    def title_id = "#{@id}-title"
    def desc_id  = "#{@id}-desc"
  end
end
