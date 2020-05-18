require 'seek/custom_exception'

class ProjectsController < ApplicationController
  include Seek::IndexPager
  include CommonSweepers
  include Seek::DestroyHandling
  include ApiHelper

  include SysMODB::SpreadsheetExtractor

  before_action :find_requested_item, only: %i[show admin edit update destroy asset_report populate populate_from_spreadsheet
                                               admin_members
                                               admin_member_roles update_members storage_report request_membership overview]
  before_action :has_spreadsheets, only: %i[:populate %populate_from_spreadsheet]
  before_action :find_assets, only: [:index]
  before_action :auth_to_create, only: %i[new create]
  before_action :is_user_admin_auth, only: %i[manage destroy]
  before_action :editable_by_user, only: %i[edit update]
  before_action :check_investigations_are_for_this_project, only: %i[update]
  before_action :administerable_by_user, only: %i[admin admin_members admin_member_roles update_members storage_report]
  before_action :member_of_this_project, only: [:asset_report], unless: :admin_logged_in?
  before_action :login_required, only: [:request_membership]
  before_action :allow_request_membership, only: [:request_membership]

  skip_before_action :project_membership_required

  cache_sweeper :projects_sweeper, only: %i[update create destroy]
  include Seek::BreadCrumbs

  include Seek::IsaGraphExtensions

  respond_to :html, :json

  api_actions :index, :show, :create, :update, :destroy

  def asset_report
    @no_sidebar = true
    project_assets = @project.assets | @project.assays | @project.studies | @project.investigations
    @types = [DataFile, Model, Sop, Presentation, Investigation, Study, Assay]
    @public_assets = {}
    @semi_public_assets = {}
    @restricted_assets = {}
    @types.each do |type|
      action = type.is_isa? ? 'view' : 'download'
      @public_assets[type] = @project.send(type.table_name).authorized_for(action, nil)
      # to reduce the initial list - will start with all assets that can be seen by the first user fouund to be in a project
      user = User.all.detect { |user| !user.try(:person).nil? && !user.person.projects.empty? }
      projects_shared = user.nil? ? [] : @project.send(type.table_name).authorized_for('download', user)
      # now select those with a policy set to downloadable to all-sysmo-users
      projects_shared = projects_shared.select do |item|
        access_type = type.is_isa? ? Policy::VISIBLE : Policy::ACCESSIBLE
        item.policy.access_type == access_type
      end
      # just those shared with sysmo but NOT shared publicly
      @semi_public_assets[type] = projects_shared - @public_assets[type]

      all = project_assets.select { |a| a.class == type }
      @restricted_assets[type] = all - (@semi_public_assets[type] | @public_assets[type])
    end

    # inlinked assets - either not linked to an assay or publication, or in the case of assays not linked to a publication or other assets
    @types_for_unlinked = [DataFile, Model, Sop, Assay]
    @unlinked_to_publication = {}
    @unlinked_to_assay = {}
    @unlinked_assets = {}
    @types_for_unlinked.each do |type|
      @unlinked_assets[type] = []
      @unlinked_to_publication[type] = []
      @unlinked_to_assay[type] = []
    end
    project_assets.each do |asset|
      next unless @types_for_unlinked.include?(asset.class)
      if asset.publications.empty?
        @unlinked_to_publication[asset.class] << asset
      end
      if (!asset.respond_to?(:assays) || asset.assays.empty?) && (!asset.is_isa? || asset.assets.empty?)
        @unlinked_to_assay[asset.class] << asset
      end
    end
    # get those that are unlinked to either
    @types_for_unlinked.each do |type|
      @unlinked_assets[type] = @unlinked_to_assay[type] & @unlinked_to_publication[type]
    end

    respond_to do |format|
      format.html { render template: 'projects/asset_report/report' }
    end
  end

  # GET /projects/1
  # GET /projects/1.xml
  def show
    respond_to do |format|
      format.html # show.html.erb
      format.rdf { render template: 'rdf/show' }
      format.xml
      format.json { render json: @project, include: [params[:include]] }
    end
  end

  # GET /projects/new
  # GET /projects/new.xml
  def new
    @project = Project.new

    possible_unsaved_data = "unsaved_#{@project.class.name}_#{@project.id}".to_sym
    if session[possible_unsaved_data]
      # if user was redirected to this 'edit' page from avatar upload page - use session
      # data; alternatively, user has followed some other route - hence, unsaved session
      # data is most probably not relevant anymore
      if params[:use_unsaved_session_data]
        # NB! these parameters are admin settings and can *occasionally* be used by super-users -
        # regular users won't (and MUST NOT) be able to use these; it's not likely for admins
        # or super-users to modify these along with participating institutions - therefore,
        # it's better not to update these from session
        #
        # this was also causing a bug: when "upload new avatar" pressed, then new picture
        # uploaded and redirected back to edit profile page; at this poing *new* records
        # in the DB for institutions that participate in this project would already be created, which is an
        # error (if the following line is ever to be removed, the bug needs investigation)
        session[possible_unsaved_data][:project].delete(:institution_ids)

        # update those attributes of a project that we want to be updated from the session
        @project.attributes = session[possible_unsaved_data][:project]
        @project.organism_list = session[possible_unsaved_data][:organism][:list] if session[possible_unsaved_data][:organism]
      end

      # clear the session data anyway
      session[possible_unsaved_data] = nil
    end
  end

  # GET /projects/1/edit
  def edit
    possible_unsaved_data = "unsaved_#{@project.class.name}_#{@project.id}".to_sym
    if session[possible_unsaved_data]
      # if user was redirected to this 'edit' page from avatar upload page - use session
      # data; alternatively, user has followed some other route - hence, unsaved session
      # data is most probably not relevant anymore
      if params[:use_unsaved_session_data]
        # NB! these parameters are admin settings and can *occasionally* be used by super-users -
        # regular users won't (and MUST NOT) be able to use these; it's not likely for admins
        # or super-users to modify these along with participating institutions - therefore,
        # it's better not to update these from session
        #
        # this was also causing a bug: when "upload new avatar" pressed, then new picture
        # uploaded and redirected back to edit profile page; at this poing *new* records
        # in the DB for institutions that participate in this project would already be created, which is an
        # error (if the following line is ever to be removed, the bug needs investigation)
        session[possible_unsaved_data][:project].delete(:institution_ids)

        # update those attributes of a project that we want to be updated from the session
        @project.attributes = session[possible_unsaved_data][:project]
        @project.organism_list = session[possible_unsaved_data][:organism][:list] if session[possible_unsaved_data][:organism]
      end

      # clear the session data anyway
      session[possible_unsaved_data] = nil
    end
  end

  # POST /projects
  # POST /projects.xml
  def create
    @project = Project.new
    @project.assign_attributes(project_params)
    @project.build_default_policy.set_attributes_with_sharing(params[:policy_attributes]) if params[:policy_attributes]

    respond_to do |format|
      if @project.save
        if params[:default_member] && params[:default_member][:add_to_project] && params[:default_member][:add_to_project] == '1'
          institution = Institution.find(params[:default_member][:institution_id])
          person = current_person
          person.add_to_project_and_institution(@project, institution)
          person.is_project_administrator = true, @project
          disable_authorization_checks { person.save }
        end
        members = params[:project][:members]
        if members.nil?
          members = []
        end
        members.each { | member|
          person = Person.find(member[:person_id])
          institution = Institution.find(member[:institution_id])
          unless person.nil? || institution.nil?
            person.add_to_project_and_institution(@project, institution)
            person.save!
          end
        }
        update_administrative_roles
        flash[:notice] = "#{t('project')} was successfully created."
        format.html { redirect_to(@project) }
        # format.json {render json: @project, adapter: :json, status: 200 }
        format.json { render json: @project, include: [params[:include]] }
      else
        format.html { render action: 'new' }
        format.json { render json: json_api_errors(@project), status: :unprocessable_entity }
      end
    end
  end

  def order_investigations
    @project = Project.find(params[:id])
    respond_to do |format|
      format.html
    end
  end

  # PUT /projects/1   , polymorphic: [:organism]
  # PUT /projects/1.xml
  def update
    if params[:project][:ordered_investigation_ids]
      a1 = params[:project][:ordered_investigation_ids]
      a1.permit!
      pos = 0
      a1.each_pair do |key, value |
        investigation = Investigation.find (value)
        investigation.position = pos
        pos += 1
        investigation.save!
      end
      respond_to do |format|
        format.html { redirect_to(@project) }
      end
      return
    end

    if @project.can_manage?(current_user)
      @project.default_policy = (@project.default_policy || Policy.default).set_attributes_with_sharing(params[:policy_attributes]) if params[:policy_attributes]
    end

    begin
      respond_to do |format|
        if @project.update_attributes(project_params)
          if Seek::Config.email_enabled && !@project.can_manage?(current_user)
            ProjectChangedEmailJob.new(@project).queue_job
          end
          expire_resource_list_item_content
          @project.reload
          flash[:notice] = "#{t('project')} was successfully updated."
          format.html { redirect_to(@project) }
          format.xml  { head :ok }
          format.json { render json: @project, include: [params[:include]] }
        #            format.json {render json: @project, adapter: :json, status: 200 }
        else
          format.html { render action: 'edit' }
          format.xml  { render xml: @project.errors, status: :unprocessable_entity }
          format.json { render json: json_api_errors(@project), status: :unprocessable_entity }
        end
      end
    end
  end

  def manage
    @projects = Project.all
    respond_to do |format|
      format.html
      format.xml { render xml: @projects }
    end
  end

  # returns a list of institutions for a project in JSON format
  def request_institutions
    # listing institutions for a project is public data, but still
    # we require login to protect from unwanted requests

    project_id = params[:id]
    institution_list = nil

    begin
      project = Project.find(project_id)
      institution_list = project.work_groups.collect { |w| [w.institution.title, w.institution.id, w.id] }
      success = true
    rescue ActiveRecord::RecordNotFound
      # project wasn't found
      success = false
    end

    respond_to do |format|
      format.json do
        if success
          render json: { status: 200, institution_list: institution_list }
        else
          render json: { status: 404, error: "Couldn't find #{t('project')} with ID #{project_id}." }
        end
      end
    end
  end

  def populate
    respond_with(@project)
  end

  def populate_from_spreadsheet
    flash[:notice] = params
    datafile = DataFile.find(params[:spreadsheet_id])
    workbook = datafile.spreadsheet
    sheet = workbook.sheets.first
    to_keep = Set.new
    sheet.rows.each do |r|
      if r.nil?
        next
      end
      r = sheet.rows[1]

      values = r.cells.collect { |c| (c.nil? ? 'NIL' : c.value) }
      investigation_index = values.find_index('Investigation')
      study_index = values.find_index('Study')
      assay_index = values.find_index('Assay')
      assignee_indices = []
      values.each_with_index {|val,i| if val.start_with?('Assign') then assignee_indices << i end}

      if investigation_index.nil? || study_index.nil? || assay_index.nil? || assignee_indices.empty?
        flash[:notice]= 'indexes missing'
        next
      end
      to_keep = Set.new

      latest_investigation = nil
      latest_study = nil
      latest_assay = nil
      sheet.rows.each do |r|
        if r.nil?
          next
        end
        if r.index == 1
          next
        end

        unless r.cell(investigation_index).nil?
          latest_investigation = r.index
        end
        unless r.cell(study_index).nil?
          latest_study = r.index
        end
        unless r.cell(assay_index).nil?
          latest_assay = r.index
        end
        is_assigned = false
        assignee_indices.each do |a|
          unless r.cell(a).nil?
            is_assigned = true
            break
          end
        end
        if is_assigned
          to_keep = to_keep | [latest_investigation, latest_study, latest_assay]
        end
      end

      flash[:alert]= to_keep

      investigation = nil
      study = nil
      assay = nil

      investigation_position = 1
      study_position = 1
      assay_position = 1

      sheet.rows.each do |r|
        if r.nil?
          next
        end
        if !to_keep.include? r.index
          next
        end

        unless r.cell(investigation_index).nil? || r.cell(investigation_index).value.empty?
          title = r.cell(investigation_index).value
          investigation = @project.investigations.select { |i| i.title == title }.first
          if investigation.nil?
            investigation = Investigation.new(title: title, projects: [@project])
          end
          investigation.position = investigation_position
          investigation_position = investigation_position + 1
          study_position = 1
          assay_position = 1
          investigation.save!
        end
        unless r.cell(study_index).nil? || r.cell(study_index).value.empty?
          title = r.cell(study_index).value
          study = investigation.studies.select { |i| i.title == title }.first
          if study.nil?
            study = Study.new(title: title, investigation: investigation)
          end
          study.position = study_position
          study_position = study_position + 1
          assay_position = 1
          study.save!
        end
        unless r.cell(assay_index).nil? || r.cell(assay_index).value.empty?
          title = r.cell(assay_index).value
          assay = study.assays.select { |i| i.title == title }.first
          if assay.nil?
            assay = Assay.new(title: title, study: study)
          end
          assay.position = assay_position
          assay_position = assay_position + 1
          assay.assay_class = AssayClass.for_type('experimental')
          assignees = []
          assignee_indices.each do |x|
            unless r.cell(x).nil?
              assignees = assignees + r.cell(x).value.split(';')
            end
          end
          known_creators = []
          other_creators = []
          assignees.each do |a|
            creator = Person.find_by email: a
            if creator.nil?
              other_creators = other_creators + [a]
            else
              known_creators = known_creators + [creator]
            end
          end
          assay.creators = known_creators
          assay.other_creators = other_creators.join(';')
          assay.save!
        end
      end
    end

    respond_with(@project) do |format|
      format.html { redirect_to project_path(@project) }
    end
  end

  def admin_members
    respond_with(@project)
  end

  def admin_member_roles
    respond_with(@project)
  end

  def update_members
    current_members = @project.people.to_a
    add_and_remove_members_and_institutions
    @project.reload
    new_members = @project.people.to_a - current_members
    Rails.logger.debug("New members added to project = #{new_members.collect(&:id).inspect}")
    if Seek::Config.email_enabled
      new_members.each do |member|
        Rails.logger.info("Notifying new member: #{member.title}")
        Mailer.notify_user_projects_assigned(member, [@project]).deliver_later
      end
    end
    flag_memberships
    update_administrative_roles

    flash[:notice] = "The members and institutions of the #{t('project').downcase} '#{@project.title}' have been updated"

    respond_with(@project) do |format|
      format.html { redirect_to project_path(@project) }
    end
  end

  def update_administrative_roles
    unless params[:project].blank?
      @project.update_attributes(project_role_params)
    end
  end

  def storage_report
    respond_with do |format|
      format.html do
        render partial: 'projects/storage_usage_content',
               locals: { project: @project, standalone: true }
      end
    end
  end

  def request_membership
    details = params[:details]
    mail = Mailer.request_membership(current_user, @project, details)
    mail.deliver_later
    MessageLog.log_project_membership_request(current_user.person,@project,details)

    flash[:notice]='Membership request has been sent'

    respond_with do |format|
      format.html{redirect_to(@project)}
    end
  end

  def overview

  end

  private

  def project_role_params
    params[:project].keys.each do |k|
      unless params[:project][k].nil?
        params[:project][k] = params[:project][k].split(',')
      else
        params[:project][k] = []
      end
    end

    params.require(:project).permit({ project_administrator_ids: [] },
                                    { asset_gatekeeper_ids: [] },
                                    { asset_housekeeper_ids: [] },
                                    pal_ids: [])
  end

  def project_params
    permitted_params = [:title, :web_page, :wiki_page, :description, { organism_ids: [] }, :parent_id, :start_date,
                        :end_date, :funding_codes]

    if User.admin_logged_in?
      permitted_params += [:site_root_uri, :site_username, :site_password, :nels_enabled]
    end

    if @project.new_record? || @project.can_manage?(current_user)
      permitted_params += [:use_default_policy, :default_policy, :default_license,
                           { members: [:person_id, :institution_id] }, { project_administrator_ids: [] },
                           { asset_gatekeeper_ids: [] }, { asset_housekeeper_ids: [] }, { pal_ids: [] }]
    end

    if params[:project][:programme_id].present? && Programme.find_by_id(params[:project][:programme_id])&.can_manage?
      permitted_params += [:programme_id]
    end

    params.require(:project).permit(permitted_params)
  end

  def check_investigations_are_for_this_project
    project_id = params[:id]
    if params[:project][:ordered_investigation_ids]
      a1 = params[:project][:ordered_investigation_ids]
      a1.permit!
      valid = true
      a1.each_pair do |key, value |
        a = Investigation.find (value)
        valid = valid && a.projects.detect(@project)
      end
      unless valid
        error("Each ordered #{"Investigation"} must be associated with the Project", "is invalid (invalid #{"Investigation"})")
        return false
      end
    end
    return true
  end


  def add_and_remove_members_and_institutions
    groups_to_remove = params[:group_memberships_to_remove] || []
    people_and_institutions_to_add = params[:people_and_institutions_to_add] || []
    groups_to_remove.each do |group|
      group_membership = GroupMembership.find(group)
      next unless group_membership && group_membership.person_can_be_removed?
      # this slightly strange bit of code is required to trigger and after_remove callback, which should be revisted
      #
      # Finn: http://guides.rubyonrails.org/association_basics.html#the-has-many-through-association
      #       "Automatic deletion of join models is direct, no destroy callbacks are triggered."
      group_membership.person.group_memberships.destroy(group_membership)
    end

    people_and_institutions_to_add.each do |new_info|
      json = JSON.parse(new_info)
      person_id = json['person_id']
      institution_id = json['institution_id']
      person = Person.find(person_id)
      institution = Institution.find(institution_id)
      unless person.nil? || institution.nil?
        person.add_to_project_and_institution(@project, institution)
        person.save!
      end
    end
  end

  def flag_memberships
    unless params[:memberships_to_flag].blank?
      GroupMembership.where(id: params[:memberships_to_flag].keys).includes(:work_group).each do |membership|
        if membership.work_group.project_id == @project.id # Prevent modification of other projects' memberships
          left_at = params[:memberships_to_flag][membership.id.to_s][:time_left_at]
          membership.update_attributes(time_left_at: left_at)
        end
        member = Person.find(membership.person_id)
        Rails.cache.delete_matched("rli_title_#{member.cache_key}_.*")
      end
    end
  end

  def editable_by_user
    @project = Project.find(params[:id])
    unless User.admin_logged_in? || @project.can_edit?(current_user)
      error('Insufficient privileges', 'is invalid (insufficient_privileges)', :forbidden)
      return false
    end
  end

  def has_spreadsheets
    @project = Project.find(params[:id])
    return !@project.spreadsheets.empty?
  end

  def member_of_this_project
    @project = Project.find(params[:id])
    if @project.nil? || !@project.has_member?(current_user)
      flash[:error] = "You are not a member of this #{t('project')}, so cannot access this page."
      redirect_to project_path(@project)
      false
    else
      true
    end
  end

  def administerable_by_user
    @project = Project.find(params[:id])
    unless @project.can_manage?(current_user)
      error('Insufficient privileges', 'is invalid (insufficient_privileges)', :forbidden)
      return false
    end
  end

  def allow_request_membership
    unless Seek::Config.email_enabled && @project.allow_request_membership?
      error('Cannot request membership of this project', 'is invalid (invalid state)')
      false
    end
  end
end
