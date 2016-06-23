/**
 *  pedestrianAPIA
 *  Author: Geoffrey Danet
 *  Description: Based on the Pedestrian model made by Carole Adam.
 */


model pedestrianAPIA


import "modelAPIA.gaml"


/***************************
 * PEDESTRIANS / RESIDENTS *
 ***************************/

species pedestrian skills:[moving] control: simple_bdi schedules: (pedestrian where not (each.is_dead or each.is_safe)){

	/***********************
	 * PHYSICAL ATTRIBUTES *
	 ***********************/
	// health, initially random value, then updated by fire dealing injuries
	int health <- 10+rnd(100) min:0;
	int initial_health <- health;
	// total received injury because no memory of initial health
	int injuries <- 0;
	float velocity min:0.2 max:8.0 <- rnd(0.6)+0.2; // get an equiprobable value in the interval [0.2; 1.0]

	// standard attributes
	rgb color <- #blue;
	rgb border <- #black;
	float size <- 0.5; // circle size
	world_cell my_cell; //cell used by the agent
	building myBuilding; // the agent's house


	/*****************************
	 * PSYCHOLOGICAL  ATTRIBUTES *
	 *****************************/

	bool knows_risks <- flip(0.5);
	bool knows_how_to_fight_fire <- flip(0.5);
	bool listens_radio <- false; // define if the agent is listening radio
	bool is_safe <- false; // define if the agent is in a safe place like a shelter
	bool is_leaving <- false; // define if the agent is leaving to a shelter
	bool is_dead <- false; // define if  the agent is dead or still alive
	bool in_smoke <- false; // define if the agent is in the in_smoke

	float determination min: 0.0 max: 1.0 <- rnd(1.0); // determination to do an action
	float persuadabillity min: 0.0 max: 1.0 <- rnd(1.0); // the agent can be more and less influenced by others agents or environment
	float danger_aversion min: 0.0 max: 1.0 <- rnd(1.0); // the agent can reject the fact that he is in a dangerous situation / is not effraid by the situation
	float perception_radius min: 0.0 max: 20.0 <- rnd(20.0); // determine the perception radius
	float defense_radius min: 0.0 <- 2.0; // determine the area of defense, if a fire enter in this area the agent begin to fight agains.
	float danger_radius min: 0.0 max: 10.0 <- rnd(10.0); // determine the danger radius

	list<fire> known_fires; // list of known fires
	list<shelter> known_shelters; // list of known shelters

	bool does_nothing <- false;
	bool goes_to_shelter <- false;
	bool takes_cover_at_home <- false;
	bool seeks_information <- false;
	bool prepares_property <- false;
	bool fights_fire <- false;
	
	int last_plan <- -1;
	bool aware <- false;

	shelter closest_shelter; // closest shelter from the agent position

	/******
	 * BDI *
	 ******/

	// Belief
	predicate belief_danger <- new_predicate("Become dangerous");
	predicate belief_shelter_position <- new_predicate("Know shelter position");
	predicate belief_fire_position <- new_predicate("Know the fire position");

	// Desire & Intention
	predicate waiting_for_event <- new_predicate("Waiting for event") with_priority rnd(1-danger_aversion);
	predicate stay_alive <- new_predicate("Stay alive") with_priority rnd(danger_aversion);
	predicate protect_property <- new_predicate("Protect their property") with_priority rnd(determination);
	predicate get_information <- new_predicate("Try to get information") with_priority rnd(danger_aversion);
	
	/********* */
	/** PLAN ***/
	/********* */

	plan do_nothing intention: waiting_for_event
	{
		self.color <- #blue;
		does_nothing <- true;
		if(!is_dead)
		{
			self.last_plan <- 0;
		}
	}

	// STAY ALIVE

	plan go_to_shelter intention: stay_alive
	{
		goes_to_shelter <- true;
		
		if(!is_dead)
		{
			self.last_plan <- 1;
		}

		self.is_leaving <- true;
		self.in_smoke <-(self.my_cell.cover in [HOTSPOT_CELL,FIRE_CELL]);

		point prev_loc <- copy(location);
		bool try_heuristic_move <- empty(known_shelters);
		bool stuck <- not ((world_cell(location).neighbors) first_with (each.cover in [EMPTY_CELL]) != nil);

		do remove_desire(protect_property);

		if(not try_heuristic_move)
		{
			bool need_to_recompute <- ((world_cell(location).neighbors) first_with (each.cover in [HOTSPOT_CELL,FIRE_CELL]) != nil) ;
			if (closest_shelter = nil)
			{
				closest_shelter <- known_shelters closest_to self;
			}
			do goto
				target: closest_shelter
				on: world_cell where (each.cover = EMPTY_CELL or /*not flip(danger_aversion) or*/ each.cover = SHELTER_CELL)
				recompute_path: need_to_recompute;
			try_heuristic_move <- prev_loc = location;
		}
		else if(try_heuristic_move)
		{
			list<fire> close_fires <- fire at_distance(perception_radius);
			if not empty(close_fires) {
				float direction <-  mean (close_fires collect float(self towards each)) - 180;
				do move heading:direction;
			}
			if (location = prev_loc) {
				do wander amplitude: 45;
			}
		}

		self.color <- (stuck and not self.myBuilding.destroyed and location = myBuilding.location) ? #silver : #aqua;
	}

	plan take_cover_at_home intention: stay_alive when: not self.myBuilding.destroyed and (self.location = self.myBuilding.location) finished_when: self.myBuilding.destroyed
	{
		if(!is_dead)
		{
			self.last_plan <- 2;
		}
		
		do remove_desire(protect_property);
		self.color <- #silver;
		takes_cover_at_home <- false;
	}

	// DEFENSE PROPERTY

	plan seek_information intention: get_information
	{
		if(!is_dead)
		{
			self.last_plan <- 3;
		}
		
		self.color <- #green;
		listens_radio <- true;
		seeks_information <- true;
	}

	/**
	 * Plan prepare property: if the agent knows how to fight fire, he can prepare the property before the fire come
	 */
	plan prepare_property when: (knows_how_to_fight_fire and empty(known_fires at_distance defense_radius) and !self.myBuilding.destroyed)
	{
		if(!is_dead)
		{
			self.last_plan <- 4;
		}
		
		self.color <- #orange;
		int preparationEffect <- rnd(people_preparation_factor);
 		// prepare house, based on objective ability - will protect it from fire damage
 		// add life points by preparing for fire, until it gets closer
		// each action adds 0-10 points, but done several times
		myBuilding.resistance <- min(
			[building_max_resistance,myBuilding.resistance+preparationEffect]
		);
		prepares_property <- true;
	}

	plan fight_fire intention: protect_property 
		when: (
			(not empty(known_fires at_distance defense_radius) 
			and has_belief(belief_fire_position))
			or (self.my_cell.cover in [HOTSPOT_CELL,FIRE_CELL])
			) 
		finished_when: empty(known_fires at_distance defense_radius)
	{
		if(!is_dead)
		{
			self.last_plan <- 5;
		}
		
		self.color <- #red;
		int fightingEffect <- int(rnd(people_fighting_factor)+(knows_how_to_fight_fire?rnd(5.0):0.0));
		int proximity_fire <- 0;
		// actually fight the fire - influenced by objective ability
		ask known_fires at_distance (defense_radius)
		{
			// objective ability influences the target radius, and intensity decrement applied to fires in that radius
			intensity <- intensity - fightingEffect;
			shape <- circle(intensity);
		}
		fights_fire <- true;
	}

 	/*****************
 	 * 	   REFLEXES       *
 	 *****************/

	reflex death when: health<= 0 and !is_dead {
		do clear_beliefs();
        do clear_desires();
        do clear_intentions();
        rgb mem <- self.color;
 		self.color <- #black;
 		self.border <- mem;
		self.is_dead <- true;
		numberDead <- numberDead+1;
	}

	reflex update_status when: !is_dead
	{
		// update known fires
		list<fire> new;
		loop current_fire over: known_fires
		{
			if(not dead(current_fire) and current_fire != nil and current_fire.intensity>0)
			{
				add current_fire to: new;
			}
		}
		known_fires <- copy(new);

		// If there aren't known fires remaining. Then, the agent doesn't belief he knows where are the fires anymore.
		if(empty(known_fires))
		{
			do remove_belief(belief_fire_position);
		}

		// the agent's speed is proportional to his health
		self.speed <- ((health*velocity)/initial_health);
		// reduce the speed when the agent is in in_smokes (20%)
		self.speed <- ((in_smoke) ? self.speed-0.2*self.speed : self.speed);

		if(has_desire(protect_property) and not is_leaving)
		{
			if(not self.myBuilding.destroyed)
			{
				// Is the situation dangerous ?
				// building_damage is a value between 0 and 1 where 0 is a safe building, and 1 is a destroyed building
				// pedestrian_injuries  is a value between 0 and 1 where 0 means the pedestrian doesn't have any injuries, and close to 1 the pedestrian has important injures
				float building_damage <- 1-(myBuilding.resistance/myBuilding.initial_resistance);
				float pedestrian_injuries <- 1-(health/initial_health);

				// if the means of the building damages and the pedestrian injuries is over the pedestrian determination
				// then the pedestrian leave the house and go to the closest shelter.
				if(mean([building_damage,pedestrian_injuries]) > determination)
		 		{
					protect_property <- new_predicate("Protect their property") with_priority (protect_property.priority-0.01);
					stay_alive <- new_predicate("Want leave") with_priority (stay_alive.priority+0.01);
		 		}
		 		else
		 		{
		 			protect_property <- new_predicate("Protect their property") with_priority (protect_property.priority+0.01);
		 			stay_alive <- new_predicate("Want leave") with_priority (stay_alive.priority-0.01);
		 		}
 			}
 			else
	 		{
	 			listens_radio <- false;
	 			do remove_desire(protect_property);
				do add_desire(stay_alive);
	 		}
 		}
	}


	/*****************
	 *    PERCEPTION    *
	 *****************/

	perceive target:(list(fire) - known_fires) in: perception_radius
	{
		add self to: myself.known_fires;
	    ask myself
	    {
	    	do add_belief(belief_fire_position);
	    	do add_desire(get_information);
		}
	}

	perceive target: known_fires in: danger_radius when: has_belief(belief_fire_position)
	{
		ask myself
		{
			aware <- true;
			do add_belief(belief_danger);
			do add_desire(protect_property);
	    	do add_desire(stay_alive);
		}
	}

	perceive target:shelter in: perception_radius
	{
		add self to: myself.known_shelters;
		myself.closest_shelter <- nil;
	}

	perceive target:pedestrian in: perception_radius when: empty(known_shelters) and self.is_leaving
	{
		if(self.is_leaving and not self.is_dead and not empty(self.known_shelters))
		{
			pedestrian focus <- self;
			ask myself
		    {
		    	if(flip(persuadabillity))
		    	{
		    		do goto target: focus; // Wait  ! Please !
		    	}
			}
		}
	}

	perceive target:shelter in: 2
	{
		ask myself
	    {
	    	do clear_beliefs();
       	 	do clear_desires();
        	do clear_intentions();
	    	if(!is_safe)
	    	{
	    		numberSheltered <- numberSheltered+1;
	    	}
			self.is_safe <- true;
			self.color <- #lime;
		}
	}

	/********
	 * RULES *
	 ********/



	/******************
	 *  ASPECT FOR GUI  *
	 ******************/

	aspect basic
	{
		draw circle(size) color: color border: border;
	}

	init
	{
		self.speed <- velocity;
		ask shelter
		{
			if(flip(0.8))
			{
				add self to: myself.known_shelters;
			}
		}
		do add_desire(waiting_for_event);
	}
}
