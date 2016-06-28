/**
 *  modelAPIA
 *  Author: bgaudou, cadam and gdanet
 *  Description: 
 */

model modelAPIA

import "Core/fire.gaml"
import "Core/pedestrian.gaml"
import "Core/world_cell.gaml" 

import "Species/pedestrianAPIA-bdi.gaml"
import "Species/pedestrianAPIA-ssc.gaml"
import "Species/pedestrian_geo_bdi.gaml"

global
{
	bool use_bdi <- true;
	bool end_sim <- false;
	bool batch_mode <- false;
	float computation_time <- machine_time;
	float global_error;
	
	bool cells_should_be_updated <- false;

	// compteurs du nombre d'agents dans les differents etats
	int numberDead <- 0;
	int numberSheltered <- 0;
	int numberDefended <- 0; 
	
	int numberDefenders <- 0;
	int numberEscapers <- 0;
	int numberIndecisive <- 0;
	int numberDestroyed <- 0;
	
	// statistics variables
	int totalDamage <- 0;
	int totalInjury <- 0;
	
	/**********************
	 * *** PARAMETERS *** * 
	 **********************/
	
	// Parameters
	int nb_people <- 200;
	int max_health <- 300;
	
	float shelter_size <- 3.0; // Shelters size
	
	// people related		
	// radius where peple with max objective ability of 1 will detect the fire
	int people_further_awareness <- 15;
	// some probability so that agents have a chance to be surprised
	float proba_detection <- 1.0;
	// max radius for counting fires when evaluating danger, for people with max risk_aversion of 1
	int people_further_aversion <- 10;
	// radius to impact fire
	int people_defense_radius <- 4;
	// multiplying factor for preparation actions and defense actions (based on objective ability)
	int people_preparation_factor <- 10;
	int people_fighting_factor <- 15;
	// motivation update rate : how fast the motivation decays in adverse condition, and increases in positive conditions
	// 0 = min speed (no change), 1= max speed (drops to 0 or increases to 1 directly) 
	float motivation_update_rate <- 0.05;
	// ability update rate : how fast the subjective ability is updated based on observations
	float ability_update_rate <- 0.3;
	
	int hotspot_path_malus <- 10;
	
	list<world_cell> forbiden_zones <- [];

	string save_trajectory_file_path <- "../results/pedestrians"+machine_time+".txt";
	string save_traj_for_analysis <- "../results/p200.txt";
	string save_csv_for_analysis <- "../results/p200.csv";
	
	float nb_in_house_D ;
	float nb_escaping_D;
	float nb_defending_D;

	list<pedestrian> pedestrians; // -> {list(pedestrian)};
	
	init
	{
		create shelter number:1 {
			location <- world_cell({95,5}).location;
			world_cell({95,5}).cover <- SHELTER_CELL;
		}
		create shelter number:1 {
			location <- world_cell({5,95}).location;
			world_cell({5,95}).cover <- SHELTER_CELL;
		}	
		
 		ask world_cell
 		{
 			if(self.cover = SHELTER_CELL)
 			{
 				forbiden_zones <- forbiden_zones + (self neighbors_at shelter_size);
			}
 		}
			
		do start_fire with: [how_many::fire_init_number];
	
	}//end init global
	 
/*******************************************/
/*************** USER COMMANDS ************/
/*******************************************/
	
	// user commands to start and stop fire
	user_command "Start some fires !!!"
	{
		int n<- 10;
        map input_values <- user_input(["How many?" :: n]);
        do start_fire how_many: int(input_values["How many?"]);
    }
    
    user_command stop_fire action: stop_fire;
	action stop_fire {
		ask fire {
			do die_properly;
		}
	}
	
/*******************************************/
/*************** ACTIONS *******************/
/*******************************************/
	 
	action start_fire(int how_many) 
	{
		create fire number:how_many
		{
			my_cell <- one_of(world_cell 
				where (
					each.cover != FIRE_CELL
					and each.cover != BUILDING_CELL
					and each.cover != SHELTER_CELL 
					and not (each in forbiden_zones)
				)
			);
			location <- my_cell.location;
			ask my_cell
			{
				my_fire <- myself;
				cover <- FIRE_CELL;
			}
		}
		// update covers and path : this boolean will trigger the reflex update_cells
		cells_should_be_updated <- true; 		
		
	}
	
	action compute_stats {
		computation_time <- machine_time - computation_time;
		int nb_dead <- pedestrians count (each.is_dead);
		write("nb_dead = "+nb_dead);
		 nb_in_house_D  <- 0.0+pedestrians count (each.in_the_house_D);
		 nb_escaping_D <- 0.0+pedestrians count (each.escaping_D);
		 nb_defending_D <-  (pedestrians count (each.is_dead)) - nb_in_house_D - nb_escaping_D;
		
		if (not batch_mode) {
			write "nb_defending_D: " + (nb_dead = 0 ? 0: nb_defending_D/ nb_dead*100) + " -> 17%";
			write "nb_escaping_D: " + (nb_dead = 0 ? 0:nb_escaping_D/ nb_dead*100) + " -> 14%";
			write "nb_in_house_D: " + (nb_dead = 0 ? 0:nb_in_house_D/ nb_dead*100) + " -> 69%"; 
		}
		if (nb_dead > 0) {
			global_error <-
			abs(17 - nb_defending_D/ nb_dead*100)+
			abs(14 - nb_escaping_D/ nb_dead*100)+
			abs(69 - nb_in_house_D/ nb_dead*100);}
		else {
			global_error <-17.0 +14+69;
		}
		
		 nb_in_house_D  <- nb_dead = 0 ? 0: nb_in_house_D/ nb_dead*100;
		 nb_escaping_D <- nb_dead = 0 ? 0: nb_escaping_D/ nb_dead*100;
		 nb_defending_D <- nb_dead = 0 ? 0: nb_defending_D/ nb_dead*100;
		
	}
	
/*******************************************/
/*************** REFLEXES *******************/
/*******************************************/
	 
	// simulation ends automatically once all people agents are dead (safe in shelter or dead in fire)
	// do not do at the start...
	reflex thatsallfolks when: cycle>2 and (empty(pedestrians where (not each.is_dead)) or empty(fire)) or (machine_time - computation_time > 500000)
	{
		if ((machine_time - computation_time > 500000)) {
			global_error <- 99999.9;
		} else {
			do compute_stats;
		}
		
		end_sim <- true;
		if (not batch_mode) {do pause;}
	}
	
	reflex update_cells when: cells_should_be_updated {
		ask world_cell {
			do update_cell_cover;
		}				
		cells_should_be_updated <- false;		
	}

}

/*******************************************/
/*************** EXPERIMENTS ***************/
/*******************************************/


experiment fire_batch type:batch repeat: 10 until:end_sim  keep_seed: true{
	parameter "use bdi" var: use_bdi among: [true, false];
	parameter "batch mode" var:batch_mode among:[true];
	reflex time_data {
		write "*** TIME : " + mean(simulations collect each.computation_time ) 
+ " nb_in_house_D:" + mean(simulations collect each.nb_in_house_D )+ " nb_escaping_D:" + mean(simulations collect each.nb_escaping_D )+ " nb_defending_D:" + mean(simulations collect each.nb_defending_D );
	}
}

experiment fire_exp type:gui {
	parameter "Initial number of people" var: nb_people min: 0 category:"Initial values";
	
	// Fire
	parameter "Fire probability to grow" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to de-grow" var: fire_proba_ungrow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to propagate" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire initial intensity" var: fire_initial_intensity min:0 max:20 category: "Fire";
	parameter "Fire maximum intensity" var: fire_max_intensity min:0 max:20 category: "Fire";
	parameter "Fire damage factor (to buildings)" var: fire_damage_factor init:3 min: 1 max: 10 category: "Fire";	
	parameter "Fire injury factor (to people)" var: fire_injury_factor init:1 min: 1 max: 10 category: "Fire";	
	parameter "Initial number of fires" var:fire_init_number init:10 min:0 max:100 category: "Fire";
	parameter "Max number of fires" var:fire_max_number init:50 min:10 max:100 category: "Fire";
	
	// People
	parameter "People furthest radius of awareness" var:people_further_awareness min: 1 init: 15 category: "People";
	parameter "Probability to detect fire in radius of awareness" var:proba_detection init:1.0 category: "People";
	parameter "People furthest radius to get aware of fire" var:people_further_aversion min:1 init: 10 category: "People";
	parameter "People max radius to impact fire" var:people_defense_radius min:1 init: 4 category: "People";
	parameter "People preparation factor (max preparation action)" var:people_preparation_factor min:1 init: 10 category:"People";
	parameter  "People fighting factor (max defense action)" var:people_fighting_factor min:1 init: 15 category:"People";
	parameter "People motivation update rate" var: motivation_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	parameter "People confidence update rate" var: ability_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	
	// Buildings
	parameter "Building maximum resistance level" var: building_max_resistance init: 300 min:0 max:300 category: "Building";
	parameter "Building resistance to be fire ready" var:building_fire_ready min:0 max:300 init:200 category: "Building";
	parameter "Building protection factor (against fire injuries)" var:building_protection_factor init:0.01 min: 0.0 max: 0.5 category: "Building";
	parameter "Building minimum protection" var:building_min_protection init:2 min:1 max:5;
	
/*******************************************/
/************* INITIALISATION ***************/
/*******************************************/
	
	init
	{
		if (use_bdi)
		{
			create pedestrianBDI number:nb_people
			{
				my_cell <- one_of(world_cell 
					where (
						each.cover != FIRE_CELL 
						and each.cover != BUILDING_CELL 
						and each.cover != SHELTER_CELL 
						and not (each in forbiden_zones)
					)
				);
				location <- my_cell.location;		
				
				create building returns: createdBuildings {
					my_cell <- myself.my_cell;
					location <- my_cell.location;
					owner <- myself;
				}
				
				myBuilding <- first(createdBuildings);
				
				ask my_cell {
					cover <- BUILDING_CELL;			
				}
				
				add self to: pedestrians;
			}
		}
		else
		{
			create pedestrianSSC number:nb_people
			{
				my_cell <- one_of(world_cell 
					where (
						each.cover != FIRE_CELL 
						and each.cover != BUILDING_CELL 
						and each.cover != SHELTER_CELL 
						and not (each in forbiden_zones)
					)
				);
				location <- my_cell.location;		
				
				create building returns: createdBuildings {
					my_cell <- myself.my_cell;
					location <- my_cell.location;
					owner <- myself;
				}
				
				myBuilding <- first(createdBuildings);
				
				ask my_cell {
					cover <- BUILDING_CELL;			
				}
				
				add self to: pedestrians;
			}		
		}
	}
	
	output 
	{
		display fire_display type: opengl
		{
	        grid world_cell lines: #black;
	        species shelter aspect: basic;	        
	        species building aspect: basic;
	        species pedestrianBDI aspect: basic;
	        species pedestrianSSC aspect: basic;
	        species fire aspect: basic;
	    } 	
	}
}

experiment exp_bdi type:gui
{
	parameter "Initial number of people" var: nb_people min: 0 category:"Initial values";
	
	// Fire
	parameter "Fire probability to grow" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to de-grow" var: fire_proba_ungrow min:0.0 max:1.0 category: "Fire";
	parameter "Fire probability to propagate" var: fire_proba_grow min:0.0 max:1.0 category: "Fire";
	parameter "Fire initial intensity" var: fire_initial_intensity min:0 max:20 category: "Fire";
	parameter "Fire maximum intensity" var: fire_max_intensity min:0 max:20 category: "Fire";
	parameter "Fire damage factor (to buildings)" var: fire_damage_factor init:3 min: 1 max: 10 category: "Fire";	
	parameter "Fire injury factor (to people)" var: fire_injury_factor init:1 min: 1 max: 10 category: "Fire";	
	parameter "Initial number of fires" var:fire_init_number init:10 min:0 max:100 category: "Fire";
	parameter "Max number of fires" var:fire_max_number init:50 min:10 max:100 category: "Fire";
	
	// People
	parameter "People furthest radius of awareness" var:people_further_awareness min: 1 init: 15 category: "People";
	parameter "Probability to detect fire in radius of awareness" var:proba_detection init:1.0 category: "People";
	parameter "People furthest radius to get aware of fire" var:people_further_aversion min:1 init: 10 category: "People";
	parameter "People max radius to impact fire" var:people_defense_radius min:1 init: 4 category: "People";
	parameter "People preparation factor (max preparation action)" var:people_preparation_factor min:1 init: 10 category:"People";
	parameter  "People fighting factor (max defense action)" var:people_fighting_factor min:1 init: 15 category:"People";
	parameter "People motivation update rate" var: motivation_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	parameter "People confidence update rate" var: ability_update_rate min:0.0 max:1.0 init:0.2 category: "People";
	
	// Buildings
	parameter "Building maximum resistance level" var: building_max_resistance init: 300 min:0 max:300 category: "Building";
	parameter "Building resistance to be fire ready" var:building_fire_ready min:0 max:300 init:200 category: "Building";
	parameter "Building protection factor (against fire injuries)" var:building_protection_factor init:0.01 min: 0.0 max: 0.5 category: "Building";
	parameter "Building minimum protection" var:building_min_protection init:2 min:1 max:5;
	
	init
	{
		create pedestrian_geo_bdi number:nb_people
		{
			my_cell <- one_of(world_cell 
				where (
					each.cover != FIRE_CELL 
					and each.cover != BUILDING_CELL 
					and each.cover != SHELTER_CELL 
					and not (each in forbiden_zones)
				)
			);
			location <- my_cell.location;
			
			create building returns: createdBuildings {
				my_cell <- myself.my_cell;
				location <- my_cell.location;
				owner <- myself;
			}
			
			myBuilding <- first(createdBuildings);
			
			ask my_cell {
				cover <- BUILDING_CELL;			
			}
			add self to: pedestrians;
		}	
	}
	
	output {
		display fire_display type: opengl {
	        grid world_cell lines: #black;
	        species shelter aspect: basic;	        
	        species building aspect: basic;
	        species pedestrian_geo_bdi aspect: basic;
	        species fire aspect: basic;
	    } 	
	}
}
