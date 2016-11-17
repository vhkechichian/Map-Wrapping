class MyMapsController < ApplicationController
  before_filter :get_user
  before_filter :authenticate_user!, :only => [:list, :show, :create, :destroy]

  def list
    @mymaps = @user.maps.order("updated_at DESC").paginate(:page => params[:page],:per_page => 8)
    @mylayers = @user.layers
    @remove_from = true
    @html_title = "#{@user.login.capitalize}'s 'My Maps' on "
  end


  def create

    if @user == current_user 
      @map = Map.find(params[:map_id])
      um = @user.my_maps.new(:map => @map)
      if um.save     
        flash[:notice] = t('.flash')
      else
        flash[:notice] = um.errors.on(:user_id)
      end

    else
      flash[:notice] = t('.others_error')
      #TODO redirect back with message
    end

    redirect_to my_maps_path
    #TODO catch when http referer is down

  end

  #we shouldnt be able to remove a map we uploaded
  def destroy
    if (@user == current_user and !current_user.own_this_map?(params[:map_id]))

      my_map = @user.my_maps.find_by_map_id(params[:map_id])

      if my_map.destroy 
        flash[:notice] = t('.flash')
      else
        flash[:notice] = t('.error')
      end
    else
      if current_user.own_this_map?(params[:map_id])
        flash[:notice]= t('.not_your_own')
      else
        flash[:notice]= t('.error')
      end

   

    end
    redirect_to my_maps_path
  end

  private
  def get_user
    @user = User.find(params[:user_id])

    if user_signed_in?
      if  @user == current_user or  current_user.has_role?("editor")
        @user
      else
        return redirect_to user_path(current_user)
      end
    else
      return redirect_to maps_path
    end

  end


end
