# Pin npm packages by running ./bin/importmap

pin "application"
pin "turbo_confirm"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "preline", to: "https://cdn.jsdelivr.net/npm/preline@2.4.1/dist/preline.min.js"
pin "apexcharts", to: "https://ga.jspm.io/npm:apexcharts@4.3.0/dist/apexcharts.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
