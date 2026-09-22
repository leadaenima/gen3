# Weather FX 6 Environmental Engine

Runtime order:

`budget -> world -> climate -> celestial -> environment -> presentation -> effects -> audio`

The **budget** stage owns adaptive transient-work pressure. **world** owns host/time/season state. **climate** owns authoritative WeatherState plus derived macro weather, microclimate and cloud-field state. **celestial** keeps one sun/moon/deep-sky owner. **environment** owns wind, atmosphere, sparse material state and transition events. **presentation** remains frame-rate live. **effects** owns follower/tornado side effects. **audio** owns the environmental acoustic model and weather sound playback.

Slow state passes use RenderGraph intervals and accumulated `dt`; they never create a second weather authority. Manual quality tiers stay exact. AUTO may reduce only transient workload and simulation frequency when frame/heap pressure persists.

Persistent environmental state is sparse. Active chunks keep full cells; sleeping chunks are flattened into compact arrays and restored on demand. External mods are never edited: reactions are exposed through read-only exports and subscriptions.
