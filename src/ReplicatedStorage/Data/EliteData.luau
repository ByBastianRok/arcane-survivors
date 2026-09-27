-- EliteData (ModuleScript) - afijos de ÉLITE que modifican a un enemigo base.
-- Se aplican MULTIPLICANDO los stats del enemigo. Dan un brillo de color y más Cash.
-- Campos (todos opcionales): Nombre (prefijo INGLES del nameplate), Vida/Velocidad/Dano
-- (multiplicadores), Escala (tamaño), Regen (vida/seg), Color (brillo), CashMult.
local EliteData = {}

EliteData.Veloz = {
	Nombre = "Swift",
	Velocidad = 1.7,
	Color = Color3.fromRGB(255, 240, 80),
	CashMult = 1.5,
}

EliteData.Acorazado = {
	Nombre = "Armored",
	Vida = 2, Dano = 1.2,
	Color = Color3.fromRGB(150, 155, 170),
	CashMult = 2,
}

EliteData.Gigante = {
	Nombre = "Giant",
	Vida = 2.2, Dano = 1.5, Escala = 2,
	Color = Color3.fromRGB(190, 70, 230),
	CashMult = 3,
}

EliteData.Regenerante = {
	Nombre = "Regen",
	Vida = 1.5, Regen = 10, -- recupera 10 de vida por segundo
	Color = Color3.fromRGB(80, 255, 130),
	CashMult = 2,
}

EliteData.Explosivo = {
	Nombre = "Volatile",
	Vida = 1.2, Dano = 1.1,
	Color = Color3.fromRGB(255, 120, 30),
	CashMult = 2,
	ExplotaAlMorir = true, RadioExplota = 14, DanoExplota = 45, -- estalla al morir
}

EliteData.Vampiro = {
	Nombre = "Leech",
	Vida = 1.6, Dano = 1.2,
	Color = Color3.fromRGB(180, 30, 60),
	CashMult = 2,
	RoboVida = true, -- se cura cuando te golpea
}

EliteData.Frenetico = {
	Nombre = "Frenzied",
	Vida = 1.3, Dano = 1.1,
	Color = Color3.fromRGB(255, 60, 20),
	CashMult = 2,
	Frenetico = true, -- mas rapido cuanta menos vida le queda
}

return EliteData
