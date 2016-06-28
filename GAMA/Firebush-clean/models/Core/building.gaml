/**
* Name: building
* Author: kustom
* Description: 
* Tags: Tag1, Tag2, TagN
*/

model building

import "../modelAPIA.gaml"

global
{
	// building related
	int building_max_resistance <- 300;
	float building_protection_factor <- 0.01;
	int building_min_protection <- 2;
	// building resistance that is enough to be left alone in the fire (end of preparation)
	int building_fire_ready <- 200;
}

species building parent: obstacle {
	pedestrian owner;
	//float destructionRate <- 0.0;
	bool destroyed <- false;
	rgb b_color <- #grey;
	
	// preparedness, vulnerability, lifepoints, altogether in one resistance attribute	
	int resistance <- 100+rnd(100);
	int initial_resistance <- resistance;
	// remember how much damage was taken
	int damage <- 0;
	
	// when all life points are lost, building turns into a ruin but stays there
	reflex getDestroyed when: !destroyed and (resistance <= 0) {
		// leave a ruin in the simulation
		b_color <- #black;
		destroyed <- true;
		resistance <- 0;
		// do die;
		numberDestroyed <- numberDestroyed+1;
	}
	
	aspect basic {
		draw square(1.5) color: b_color border: #black;
	}
}