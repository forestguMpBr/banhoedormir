BathSleep = {}

BathSleep.AdminPermission = "Admin"
BathSleep.DataKey = "BathSleep:Locations"
BathSleep.RewardItem = "dollar"
BathSleep.MaxReward = 100000000

BathSleep.Commands = {
	Panel = "locaisbd"
}

BathSleep.Keys = {
	Interact = 38,
	Cancel = 73
}

BathSleep.Marker = {
	DrawDistance = 18.0,
	InteractDistance = 1.7,
	Type = 2,
	Scale = vec3(0.28,0.28,0.18),
	BathColor = { 42, 160, 255, 180 },
	SleepColor = { 134, 255, 104, 180 }
}

BathSleep.Types = {
	bath = {
		Label = "Banho",
		Verb = "tomar banho",
		DefaultDuration = 12000,
		DefaultPrice = 0,
		DefaultReward = 0,
		Effects = { Health = 5, Hunger = 0, Thirst = 0, Stress = 25 },
		Animation = {
			Dict = "mp_safehouseshower@male@",
			Name = "male_shower_idle_a",
			Flags = 1,
			Scenario = "WORLD_HUMAN_BUM_WASH"
		},
		Prop = {
			Enabled = true,
			Models = { "prop_toilet_soap_01", "prop_soap_disp_01", "prop_soap_disp_02" },
			Bone = 57005,
			Offset = vec3(0.10,0.02,-0.02),
			Rotation = vec3(-80.0,12.0,22.0)
		},
		Sound = {
			Enabled = true,
			Name = "rain",
			Volume = 0.28
		},
		ProgressLabel = "Tomando banho"
	},
	sleep = {
		Label = "Dormir",
		Verb = "dormir",
		DefaultDuration = 18000,
		DefaultPrice = 0,
		DefaultReward = 0,
		Effects = { Health = 25, Hunger = 10, Thirst = 10, Stress = 35 },
		Animation = {
			Dict = "amb@world_human_sunbathe@female@back@idle_a",
			Name = "idle_a",
			Flags = 1,
			ZOffset = -0.5
		},
		ProgressLabel = "Dormindo"
	}
}

BathSleep.DefaultLocations = {
	{
		Id = "bath-1",
		Type = "bath",
		Name = "Banho - Hotel",
		Coords = { x = 303.15, y = -1443.19, z = 29.8, w = 139.98 },
		Duration = 12000,
		Price = 0,
		Reward = 0,
		Effects = { Health = 5, Hunger = 0, Thirst = 0, Stress = 25 },
		Enabled = true
	},
	{
		Id = "sleep-1",
		Type = "sleep",
		Name = "Dormir - Leito",
		Coords = { x = 316.03, y = -1451.2, z = 29.8, w = 139.98 },
		Duration = 18000,
		Price = 0,
		Reward = 0,
		Effects = { Health = 25, Hunger = 10, Thirst = 10, Stress = 35 },
		Enabled = true
	}
}

-----------------------------------------------------------------------------------------------------------------------------------------
-- NECESSIDADES
-----------------------------------------------------------------------------------------------------------------------------------------
BathSleep.Needs = {
    -- Sujeira: quanto cada evento adiciona (0-100)
    DirtGain = {
        Ragdoll  = 15,   -- rolar no chão / ser atropelado
        Damage   = 10,   -- tomar dano (tiro, explosão)
        Water    = 5,    -- nadar / entrar na água
        Mud      = 2,    -- andar em terra/lama/areia
    },
    DirtCooldown = 8000, -- ms entre ganhos de sujeira

    -- Avisos de sujeira
    DirtWarn = {
        [30] = { msg = 'Voce esta ficando sujo. Tome um banho em breve.',      type = 'inform' },
        [60] = { msg = 'Voce esta muito sujo! Tome um banho.',                  type = 'error'  },
        [85] = { msg = 'Voce esta extremamente sujo! Tome um banho agora!',     type = 'error'  },
    },

    -- Sono: 5400s reais = 100 (1h30)
    SleepInterval = 54000, -- ms por ponto de sono (+1 a cada 54s)
    SleepWarn = {
        [50] = { msg = 'Voce esta com sono. Durma em breve.',    type = 'inform' },
        [75] = { msg = 'Voce esta muito cansado! Precisa dormir.', type = 'error'  },
        [90] = { msg = 'Voce esta exausto! Durma agora!',          type = 'error'  },
    },

    -- Stress por minuto proporcional ao nível (máx 3 pontos/min a 100%)
    MaxStressPerMinute = 3,
}

-- Comando de teste (remova em produção)
BathSleep.TestCommand = "testsujo"  -- /testsujo 85 → seta sujeira para 85
