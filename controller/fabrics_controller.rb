class FabricsController < ApplicationController
  
  layout "admin" , except: [:showcase]
  
  before_filter :authenticate_user! , except: [:load_more,:paginate,:fabrics_paginate,:showcase,:show,:filter_fabrics]

  authorize_resource

  skip_authorize_resource only: [:fabrics_paginate,:filter_fabrics]


  #auto complete for pattern
  def autocomplete_fabrics_pattern
    fabric = Fabric.where("pattern IS NOT NULL").pluck(:pattern).uniq
    render :layout=>false, :json => fabric
  end

  def drafts
    add_by_role = params[:tailor].present? ? "tailor" : "admin"
    @fabrics = Fabric.filter_draft_by_user_id_and_role(current_user, add_by_role).order(:name)
  end

  def new
    @fabric = Fabric.new
    @fabric.build_wash_instruction
    @fabric.tailor_fabrics.build
  end

  def create
    @fabric = Fabric.new permitted
    if params[:fabric][:status].present? && params[:fabric][:status] == Fabric::DRAFT
      @fabric.save(validate: false)
    else
      @fabric.save
    end
  end

  def edit
    @fabric = Fabric.find params[:id]
    @fabric.build_wash_instruction unless @fabric.wash_instruction.present?
  end

  def update
    @fabric = Fabric.find params[:id]
    @fabric.update_attributes permitted
    @fabrics = Fabric.filter_draft_by_user_id_and_role(current_user, "admin").order(:name) if params[:fabric_nav] == Fabric::DRAFT
  end

  def destroy
    @fabric = Fabric.find params[:id]
    @fabric.destroy
  end

  # use with Ajax only
  # used by fabric build tool in Designer
  def paginate
    if request.xhr?.nil? # to prevent errors by google bot that doesn't fetch using ajax
      render nothing: true
    end
    # params[:page] = params[:page].present? ? params[:page] : 1
    @fabric_search = FabricSearch.new(
      name: params[:tailor_reference],
      color_id: params[:color_id],
      pattern_id: params[:pattern_id],
      material_id: params[:material_id],
      finish_name: params[:finish_name]
    )
    
    @all_fabrics = @fabric_search.search
    @total_fabrics = @all_fabrics.count
    @fabrics = @all_fabrics.page(params[:page]).per(16)
  end

  # used in /fabrics/showcase view
  def fabrics_paginate
    render nothing: true and return if request.xhr?.nil?
    @fabrics = Fabric.filtered_fabrics(color_id: params[:color_id],pattern_id: params[:pattern_id],material_id: params[:material_id], finish_name: params[:finish_name]).page(params[:page]).per(9)
  end

  def filter_fabrics
    @fabrics = Fabric.filtered_fabrics(color_id: params[:color_id],pattern_id: params[:pattern_id],material_id: params[:material_id], finish_name: params[:finish_name]).page(params[:page]).per(9)
  end

  # Overview page of all fabrics
  def showcase
    @page = { title_key: 'title_fabrics' }
    @fabrics = Fabric.for_showcase.order( 'fabrics.name ASC' ).page(params[:page]).per(9)
  end

  # Detail view of Fabric (modal popup)
  def show
    @fabric = Fabric.find params[:id]
    if @fabric.nil? || request.xhr?.nil? # to prevent errors by google bot that fetches unavailable pages and or not via ajax
      render nothing: true
    end
  end

  def load_more
    @fabrics = Fabric.where(id: TailorFabric.pluck(:fabric_id).uniq).authenticated.order( 'fabrics.name ASC' ).page(params[:page]).per(20)
    @fab_color_filter = Color.where("code IS NOT NULL")
    @fab_pattern_filter = Pattern.where('name is not null')
    @fab_material_filter = Material.where('name is NOT NULL')
    @fab_finish_filter = Fabric.select(:desc_finish).distinct.where('desc_finish is NOT NULL')
    @part = params[:part]
    @com = params[:com]
    @shirt = params[:shirt]
  end

  def components_parts
    @fabric = Fabric.find(params[:fabric][:id])
    @fabric.component_query = params[:fabric][:component_query]
    @fabric.update_attributes! permitted
    redirect_to :back
  end

  private
    def permitted
      params.require(:fabric).permit(:id, :component_query,:name, :temp_component_file ,:file,:file_2,:price,:color,:pattern_id,:color_id,:material_id,:description, :display_name,:tailor_reference, :add_by, :approve, :add_by_user_id, :available, :status ,wash_instruction_attributes: [:fabric_id,:hand_wash,:dry_clean,:iron_temperature,:wash_able,:wash_temperature,:wash_type, :tumble_able,:tumble_type, :iron_able], tailor_fabrics_attributes: [:id,:fabric_id,:tailor_id,:tailor_price,:fabic_reference, :available])
    end
end
