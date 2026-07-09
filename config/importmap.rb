# Pin npm packages by running ./bin/importmap

pin "application"
pin "turbo_confirm"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "apexcharts", to: "https://ga.jspm.io/npm:apexcharts@4.3.0/dist/apexcharts.esm.js"
pin "signature_pad", to: "https://ga.jspm.io/npm:signature_pad@5.0.4/dist/signature_pad.umd.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@floating-ui/dom", to: "https://cdn.jsdelivr.net/npm/@floating-ui/dom@1.7.6/+esm"
pin "focus-trap" # @8.2.2
pin "body-scroll-lock" # @4.0.0
pin "motion", to: "https://cdn.jsdelivr.net/npm/motion@12.42.2/+esm"
pin "air-datepicker", to: "https://esm.sh/air-datepicker@3.6.0"
pin "air-datepicker/locale/en", to: "https://esm.sh/air-datepicker@3.6.0/locale/en"
pin "tom-select", to: "https://cdn.jsdelivr.net/npm/tom-select@2.6.1/+esm"
pin "tabbable" # @6.5.0
