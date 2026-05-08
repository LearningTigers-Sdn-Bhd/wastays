# Pin npm packages by running ./bin/importmap

pin "application"
pin "turbo_confirm"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "preline", to: "https://cdn.jsdelivr.net/npm/preline@2.4.1/dist/preline.min.js"
pin "apexcharts", to: "https://ga.jspm.io/npm:apexcharts@4.3.0/dist/apexcharts.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@floating-ui/dom", to: "@floating-ui--dom.js" # @1.7.6
pin "@floating-ui/core", to: "@floating-ui--core.js" # @1.7.5
pin "@floating-ui/utils", to: "@floating-ui--utils.js" # @0.2.11
pin "@floating-ui/utils/dom", to: "@floating-ui--utils--dom.js" # @0.2.11
