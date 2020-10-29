class StudiesController < ApplicationController
  include Seek::IndexPager
  include Seek::AssetsCommon

  before_action :studies_enabled?
  before_action :find_assets, only: [:index]
  before_action :find_and_authorize_requested_item, only: %i[edit update destroy manage manage_update show new_object_based_on_existing_one]

  # project_membership_required_appended is an alias to project_membership_required, but is necesary to include the actions
  # defined in the application controller
  before_action :project_membership_required_appended, only: [:new_object_based_on_existing_one]

  before_action :check_assays_are_not_already_associated_with_another_study, only: %i[create update]

  include Seek::Publishing::PublishingCommon
  include Seek::AnnotationCommon
  include Seek::IsaGraphExtensions

  api_actions :index, :show, :create, :update, :destroy

  def new_object_based_on_existing_one
    @existing_study = Study.find(params[:id])

    if @existing_study.can_view?
      @study = @existing_study.clone_with_associations
      unless @existing_study.investigation.can_edit?
        @study.investigation = nil
        flash.now[:notice] = "The #{t('investigation')} associated with the original #{t('study')} cannot be edited, so you need to select a different #{t('investigation')}"
      end
      render action: 'new'
    else
      flash[:error] = "You do not have the necessary permissions to copy this #{t('study')}"
      redirect_to study_path(@existing_study)
    end
  end

  def edit
    @study = Study.find(params[:id])
    respond_to do |format|
      format.html
      format.xml
    end
  end

  def update
    @study = Study.find(params[:id])
    @study.attributes = study_params
    update_sharing_policies @study
    update_relationships(@study, params)

    respond_to do |format|
      if @study.save
        flash[:notice] = "#{t('study')} was successfully updated."
        format.html { redirect_to(@study) }
        format.json {render json: @study, include: [params[:include]]}
      else
        format.html { render action: 'edit', status: :unprocessable_entity }
        format.json { render json: json_api_errors(@study), status: :unprocessable_entity }
      end
    end
  end

  def show
    @study = Study.find(params[:id])

    respond_to do |format|
      format.html
      format.xml
      format.rdf { render template: 'rdf/show' }
      format.json {render json: @study, include: [params[:include]]}
    end
  end

  def create
    @study = Study.new(study_params)
    update_sharing_policies @study
    update_relationships(@study, params)
    ### TO DO: what about validation of person responsible? is it already included (for json?)
    if @study.save
      respond_to do |format|
        flash[:notice] = "The #{t('study')} was successfully created.<br/>".html_safe
        format.html { redirect_to study_path(@study) }
        format.json { render json: @study, include: [params[:include]] }
      end
    else
      respond_to do |format|
        format.html { render action: 'new', status: :unprocessable_entity }
        format.json { render json: json_api_errors(@study), status: :unprocessable_entity }
      end
    end
  end

  def investigation_selected_ajax
    if (investigation_id = params[:investigation_id]).present? && params[:investigation_id] != '0'
      investigation = Investigation.find(investigation_id)
      people = investigation.projects.collect(&:people).flatten
    end

    people ||= []

    render partial: 'studies/person_responsible_list', locals: { people: people }
  end

  def check_assays_are_not_already_associated_with_another_study
    assay_ids = params[:study][:assay_ids]
    study_id = params[:id]
    if assay_ids
      valid = !assay_ids.detect do |a_id|
        a = Assay.find(a_id)
        !a.study.nil? && a.study_id.to_s != study_id
      end
      unless valid
        unless valid
          error("Cannot add an #{t('assays.assay')} already associated with a Study", "is invalid (invalid #{t('assays.assay')})")
          return false
        end
      end
    end
  end

  def batch_uploader

  end

  def preview_content
    tempzip_path = params[:content_blobs][0][:data].tempfile.path
    data_files, studies = Study.unzip_batch tempzip_path

    study_filename = studies.first.name
    studies_file = ContentBlob.new
    studies_file.tmp_io_object=File.open("#{Rails.root}/tmp/#{study_filename}")
    studies_file.original_filename="#{study_filename}"
    studies_file.save!
    @studies = Study.extract_studies_from_file(studies_file)
    render "studies/batch_preview"
  end

  private
  def validate_person_responsible(p)
    if (!p[:person_responsible_id].nil?) && (!Person.exists?(p[:person_responsible_id]))
      render json: {error: "Person responsible does not exist", status: :unprocessable_entity}, status: :unprocessable_entity
      return false
    end
    true
  end

  def study_params
    params.require(:study).permit(:title, :description, :experimentalists, :investigation_id, :person_responsible_id,
                                  :other_creators, { creator_ids: [] }, { scales: [] }, { publication_ids: [] },
                                  { custom_metadata_attributes: determine_custom_metadata_keys })
  end
end
