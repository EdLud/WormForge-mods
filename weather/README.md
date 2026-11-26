# Weather

Clear skies, rain and snow for any profile: select the **Weather** add-on and
give each its share with **Clear**, **Rain** and **Snow**, which add up to
100. A turn cycle ends once every team has had a turn; at the start of each
one the weather is picked again by the shares, so it may stay or change. A
weather with all 100 is there all match.

Rain falls in layers, splashes on the ground and rings the water and puddles,
each ring stopping at the shore. How heavy it is moves at random between
**Rain heaviness, lowest** and **highest**, ramping from one level to the next
over **Rain heaviness changes every**, and its sound gets louder as it gets
heavier. Lightning lights up the clouds and the
sky behind the land and acts as the Lightning Strike does. It aims at mines,
oil drums and crates first, else at worms and graves.

Snow drifts down behind the land from white clouds. On the ground it comes
anywhere on the map, under ledges and in caves too, a pixel or a 2x2 square at
a time. Half of it builds up as land: worms stand on it, dig it and blow it
up. It slides off steep steps and drifts at their foot, and when the land under
it is blown away it falls to the land below. The other half frosts the land up
to 10 pixels in, and stays. Settled snow has a faint glow. It needs the
Direct3D 9 (shader) renderer to show white; without it, settled snow takes the
nearest colour of the land.

At the start of each clear or rainy turn, **Melt** percent of the snowy ground
loses its top pixel of snow, twice as much in rain. A girder placed through
settled snow loses those pixels when the snow under it melts.

The rain sound is from Project X's Rain weather, the blizzard sound from
Project X's weather sounds. The lightning is Project X's Lightning Strike, from
`wf-lib/lightning` in the WormBench shared helpers.

`tools/make_weather_art.py` draws the sprites; the tests are in
`tests/weather/`.
