# Weather

Rain, snow and a weather cycle for any profile: select the **Rain**, **Snow**
or **Weather cycle** add-ons.

Rain falls in layers, splashes on the ground and rings the water and puddles,
each ring stopping at the shore. Lightning lights up the clouds and the sky
behind the land. With **Lightning** set to `strike`, the lightning acts as the
Lightning Strike does. It aims at mines, oil drums and crates first, else at
worms and graves.

Snow drifts down behind the land from white clouds. With **Settling snow** on,
it builds up a pixel at a time on open ground as land: worms stand on it, dig
it and blow it up. It slides off steep steps and drifts at their foot, and
when the land under it is blown away it falls to the land below. It needs the
Direct3D 9 (shader) renderer to show white; without it, settled snow takes the
nearest colour of the land.

**Weather cycle** changes the weather between rain, snow and clear spells; select
Rain or Snow with it to change how they look. A turn cycle ends once every team has had a turn; at its start
the weather may change, and settled snow melts from the top while it isn't
snowing. A girder placed through settled snow loses those pixels when the snow
under it melts.

The rain sound is from Project X's Rain weather, the blizzard sound from
Project X's weather sounds. The lightning is Project X's Lightning Strike, from
`wf-lib/lightning` in the WormForge shared helpers.

`tools/make_weather_art.py` draws the sprites; the tests are in
`tests/weather/`.
