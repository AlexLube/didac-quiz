<?php
/**
 * DidacCine · Tarjeta «Reto de cine de hoy» (Quiz)
 * Pegar en WPCode como fragmento PHP, «Ejecutar en todas partes».
 * - Añade la tarjeta al final de cada ficha (entradas), salvo La Butaca (cat 812) y Noticias (cat 59).
 * - Shortcode [didacine_quiz] para ponerla donde quieras (portada, páginas).
 * Para quitarla: desactivar el fragmento.
 */
if ( ! defined( 'ABSPATH' ) ) { exit; }

function dcq_quiz_card() {
	$url = 'https://quiz.didacine.com/?utm_source=didacine&utm_medium=tarjeta';
	ob_start(); ?>
<div class="dcq-card" role="region" aria-label="Reto de cine de hoy">
	<div class="dcq-inner">
		<div class="dcq-top">
			<span class="dcq-tag">En cartel hoy</span>
			<span class="dcq-date" data-dcq-date></span>
		</div>
		<p class="dcq-title">Reto de cine de hoy</p>
		<p class="dcq-text">10 preguntas con fotogramas, bandas sonoras y tráileres. Un reto nuevo cada día, gratis.</p>
		<a class="dcq-btn" href="<?php echo esc_url( $url ); ?>" target="_blank" rel="noopener">&#9654;&nbsp; Jugar el reto</a>
	</div>
</div>
<?php
	return ob_get_clean();
}
add_shortcode( 'didacine_quiz', 'dcq_quiz_card' );

add_filter( 'the_content', function ( $content ) {
	if ( ! is_singular( 'post' ) || ! in_the_loop() || ! is_main_query() ) { return $content; }
	if ( has_category( array( 812, 59 ) ) ) { return $content; }
	return $content . dcq_quiz_card();
}, 99 );

add_action( 'wp_footer', function () { ?>
<style id="dcq-css">
.dcq-card{--dcq-a:#f2d8a0;--dcq-b:#b9a6ff;--dcq-tag:#6d5bd0;position:relative;max-width:640px;margin:2rem auto;padding:10px;border-radius:24px;background:#110e17;
 box-shadow:0 0 30px -8px rgba(142,124,255,.35),0 12px 22px rgba(0,0,0,.45);border:1.2px solid rgba(242,216,160,.45);font-family:inherit}
.dcq-card::before{content:"";position:absolute;inset:3px;border-radius:21px;pointer-events:none;border:3px dotted var(--dcq-a);opacity:.45}
.dcq-card{padding:11px}
.dcq-inner{position:relative;background:#0b0910;border-radius:15px;border:1px solid rgba(255,255,255,.06);padding:18px 20px 20px;color:#fbf6ec}
.dcq-top{display:flex;justify-content:space-between;align-items:center}
.dcq-tag{background:var(--dcq-tag);color:#fff;font-weight:800;font-size:11px;letter-spacing:1.4px;text-transform:uppercase;padding:4px 10px;border-radius:6px}
.dcq-date{color:#a59eb4;font-size:15px;letter-spacing:1px}
.dcq-title{margin:14px 0 6px!important;font-size:32px;line-height:1;font-weight:800;text-transform:uppercase;letter-spacing:.5px;
 background:linear-gradient(135deg,#ffe9a8,#f2c14e,#c8902e);-webkit-background-clip:text;background-clip:text;color:transparent}
.dcq-text{margin:0 0 16px!important;color:#cfc8dc;font-size:15px;line-height:1.45}
.dcq-btn{display:flex;justify-content:center;align-items:center;height:52px;border-radius:16px;text-decoration:none!important;
 background:linear-gradient(135deg,#ffe9a8,#f2c14e,#c8902e);color:#241705!important;font-weight:800;letter-spacing:2px;text-transform:uppercase;font-size:17px;
 box-shadow:0 0 22px -4px rgba(242,193,78,.55);transition:transform .12s}
.dcq-btn:hover{transform:translateY(-1px)}
/* Temas por fecha, igual que en la app */
.dcq-card.t-halloween{--dcq-a:#ff8a2a;--dcq-b:#9b6bff;--dcq-tag:#e0641a;border-color:rgba(255,138,42,.5)}
.dcq-card.t-navidad{--dcq-a:#ff5a5f;--dcq-b:#3cc184;--dcq-tag:#c62a3a;border-color:rgba(255,90,95,.5)}
.dcq-card.t-sanvalentin{--dcq-a:#ff6f9c;--dcq-b:#ffc7d6;--dcq-tag:#d6336c;border-color:rgba(255,111,156,.5)}
.dcq-card.t-verano{--dcq-a:#4fd8c8;--dcq-b:#ffb27a;--dcq-tag:#169c8e;border-color:rgba(79,216,200,.5)}
.dcq-card.t-vueltaalcole{--dcq-a:#ffd25a;--dcq-b:#6cb6ff;--dcq-tag:#2f7fd8;border-color:rgba(108,182,255,.5)}
</style>
<script>
(function(){var d=new Date(),md=(d.getMonth()+1)*100+d.getDate(),t='';
if(md>=1201||md<=106)t='navidad';else if(md>=1024&&md<=1101)t='halloween';else if(md>=207&&md<=214)t='sanvalentin';
else if(md>=901&&md<=915)t='vueltaalcole';else if(md>=701&&md<=831)t='verano';
var p=function(n){return(n<10?'0':'')+n},s=p(d.getDate())+'·'+p(d.getMonth()+1)+'·'+d.getFullYear();
document.querySelectorAll('.dcq-card').forEach(function(c){if(t)c.classList.add('t-'+t);var e=c.querySelector('[data-dcq-date]');if(e)e.textContent=s;});})();
</script>
<?php } );
