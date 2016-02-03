#encoding: utf-8
require 'rubygems'
require 'rake'
require 'active_record/fixtures'
require 'colorize'
require 'seek/mime_types'

include Seek::MimeTypes

namespace :seek do

  #these are the tasks required for this version upgrade
  task :upgrade_version_tasks => [
           :environment
       ]

  #these are the tasks that are executes for each upgrade as standard, and rarely change
  task :standard_upgrade_tasks => [
           :environment,
           :clear_filestore_tmp,
           :repopulate_auth_lookup_tables,
           :resynchronise_ontology_types
       ]

  desc("upgrades SEEK from the last released version to the latest released version")
  task(:upgrade => [:environment, "db:migrate", "tmp:clear"]) do

    solr=Seek::Config.solr_enabled
    Seek::Config.solr_enabled=false

    Rake::Task["seek:standard_upgrade_tasks"].invoke
    Rake::Task["seek:upgrade_version_tasks"].invoke

    Seek::Config.solr_enabled = solr
    if (solr)
      Rake::Task["seek:reindex_all"].invoke
    end

    puts "Upgrade completed successfully"
  end

end
