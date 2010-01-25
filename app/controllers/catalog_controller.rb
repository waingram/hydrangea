require 'mediashelf/active_fedora_helper'
class CatalogController
  
  include Stanford::SaltControllerHelper
  include MediaShelf::ActiveFedoraHelper
  
  before_filter :require_solr, :require_fedora, :only=>[:show, :edit]
  before_filter :deny_to_private, :only =>[:show, :edit]
  before_filter :enforce_viewing_context_for_show_requests, :only=>:show
  before_filter :enforce_edit_permissions, :only=>:edit
  
  def edit
    @document_fedora = Document.load_instance(params[:id])
    #fedora_object = ActiveFedora::Base.load_instance(params[:id])
    #params[:action] = "edit"
    @downloadables = downloadables( @document_fedora )
    session[:viewing_context] = "edit"
    show_with_customizations
    render :action=>:show
  end
  
  # get search results from the solr index
  def index
      @extra_controller_params ||= {}
      enforce_search_permissions
      @response = get_search_results( @extra_controller_params )
      @filters = params[:f] || []
    respond_to do |format|
      format.html { save_current_search_params }
      format.rss  { render :layout => false }
    end
    rescue RSolr::RequestError
      logger.error("Unparseable search error: #{params.inspect}" ) 
      flash[:notice] = "Sorry, I don't understand your search." 
      redirect_to :action => 'index', :q => nil , :f => nil
    rescue 
      logger.error("Unknown error: #{params.inspect}" ) 
      flash[:notice] = "Sorry, you've encountered an error. Try a different search." 
      redirect_to :action => 'index', :q => nil , :f => nil
  end
    
  def show_with_customizations
    show_without_customizations
    find_folder_siblings
    #facets_for_lookup = {:fields=>['title_facet', 'technology_facet', 'person_facet']}
    params = {:qt=>"dismax",:q=>"*:*",:rows=>"0",:facet=>"true", :facets=>{:fields=>Blacklight.config[:facet][:field_names]}}
    @facet_lookup = Blacklight.solr.find params
  end
  
  # trigger show_with_customizations when show is called
  # This has the same effect as the (deprecated) alias_method_chain :show, :find_folder_siblings
  alias_method :show_without_customizations, :show
  alias_method :show, :show_with_customizations
  
  private
  
  # If someone hits the show action while their session's viewing_context is in edit mode, 
  # this will redirect them to the edit action.
  # If they do not have sufficient privileges to edit documents, it will silently switch their session to browse mode.
  def enforce_viewing_context_for_show_requests    
    if params[:viewing_context] == "browse"
      session[:viewing_context] = params[:viewing_context]
    elsif session[:viewing_context] == "edit"
      if editor?
        redirect_to :action=>:edit
      else
        session[:viewing_context] = "browse"
        #flash[:message] = "You do not have sufficient privileges to edit this document."
      end
    end
  end
  
  def enforce_search_permissions
    if !reader? 
      @extra_controller_params[:qt] = Blacklight.config[:public_qt]
      return @extra_controller_params
    end
  end
  
  def enforce_edit_permissions
    if !editor?
      session[:viewing_context] = "browse"
      flash[:notice] = "You do not have sufficient privileges to edit this document. You have been redirected to the read-only view."
      redirect_to :action=>:show
    end
  end

  def deny_to_private
    unless session[:user]
      flash[:notice] = "You must be logged in and have access to view this material."
      redirect_to :action => 'index', :q => nil , :f => nil
    end
  end


  def get_search_results(extra_controller_params={})
    _search_params = self.solr_search_params(extra_controller_params)
    index = _search_params[:qt] == 'fulltext' ? :fulltext : :default
    Blacklight.solr(index).find(_search_params)
  end

end
