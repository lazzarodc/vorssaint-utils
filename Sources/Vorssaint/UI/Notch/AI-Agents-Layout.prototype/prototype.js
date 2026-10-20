// THROWAWAY UI experiment. No native commands, API calls, storage or real mutations.
const $ = selector => document.querySelector(selector);
const escapeHTML = text => String(text).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const variants = {
  A: {name:'Fila de atenção', description:'Uma página contínua para sessões e pendências. O rodapé reúne percentual livre e tempo até a renovação; um ícone abre limites, consumo e histórico.', gain:'A pendência é acionável na abertura, sem um segundo acesso a uso no fim da lista.', tradeoff:'Com muitas pendências, a fila cresce. Consumo e histórico ficam a um clique no ícone do rodapé.'},
  B: {name:'Sessões / Uso', description:'Duas áreas com propósitos distintos. Sessões abre por padrão; Uso reúne limites, consumo e histórico. Uma faixa avisa quando a capacidade exige atenção.', gain:'Mais espaço útil para sessões e para análise, cada uma em seu momento.', tradeoff:'Consultar consumo custa uma troca de área. O alerta precisa continuar visível fora de Sessões.'},
  C: {name:'Lista + conversa', description:'Uma lista estreita mantém as sessões à vista; o painel ao lado mostra apenas a conversa selecionada. Limites e acesso ao uso ficam na base.', gain:'Trocar de conversa não exige voltar de uma tela de detalhe. Favorece várias sessões simultâneas.', tradeoff:'Divide a largura da ilha. Com 480 px, mensagens e ações ficam mais apertadas.'}
};
const param = new URLSearchParams(location.search);
const state = {variant: variants[param.get('variant')] ? param.get('variant') : 'A', scenario:'attention', width:560, area:'sessions', detail:null, selected:'claude-1', period:'Hoje', capacity:'limits', notice:'', sessions:[]};
function fixture(scenario) {
  const sessions = [
    {id:'claude-1',provider:'Claude',project:'vorssaint-utils',topic:'Integração de sessões',model:'Sonnet',terminal:'iTerm',status:'waiting',pending:true,activity:'Precisa executar os testes',elapsed:'12 min',branch:'feat/agents'},
    {id:'codex-1',provider:'Codex',project:'vorssaint-utils',topic:'Layout dos cards',model:'GPT',terminal:'iTerm',status:'working',pending:false,activity:'Reorganizando a hierarquia dos cards',elapsed:'8 min',branch:'feat/layout'}
  ];
  if(scenario==='working' || scenario==='critical') Object.assign(sessions[0], {status:'working',pending:false,activity:'Executando os testes de sessões'});
  if(scenario==='many') {
    sessions.push(...Array.from({length:4}, (_,i) => ({id:`extra-${i}`,provider:i%2?'Codex':'Claude',project:'vorssaint-utils',topic:['Documentação','Ajustes de áudio','Revisão de código','Cobertura de testes'][i],model:i%2?'GPT':'Sonnet',terminal:'iTerm',status:i===3?'idle':'working',pending:false,activity:i===3?'Sem atividade recente':'Trabalhando na tarefa',elapsed:`${17+i*3} min`,branch:`task/${i+1}`})));
  }
  return scenario==='empty' ? [] : sessions;
}
const statusText = s => s.pending ? 'Aprovação pendente' : ({working:'Trabalhando',waiting:'Aguardando você',idle:'Ociosa'}[s.status]);
const mark = s => `<span class="mark ${s.provider==='Codex'?'codex':''}" aria-hidden="true">${s.provider==='Codex'?'◈':'✳'}</span>`;
const dot = s => `<span class="dot ${s.pending?'waiting':s.status}" aria-hidden="true"></span>`;
const sessions = () => [...state.sessions].sort((a,b) => Number(b.pending)-Number(a.pending));
const pending = () => state.sessions.filter(s=>s.pending).length;
const critical = () => state.scenario==='critical';
const codexRemaining = () => critical()?8:76;
const selectedSession = () => state.sessions.find(s=>s.id===state.selected) ?? sessions()[0];
const button = (label, action, extra='', classes='pill-btn') => `<button class="${classes}" data-action="${action}" ${extra}>${label}</button>`;
function empty() {return '<div class="empty-state"><div class="empty-symbol" aria-hidden="true">◇</div><h3>Nenhuma sessão aberta</h3><p>Abra Claude ou Codex no seu terminal. O consumo continua disponível aqui.</p></div>';}
function alert() {return critical()?`<div class="limit-alert"><span>Codex: 8% da sessão restante. Renova em 1h 14m.</span>${button('Ver','capacity','','text-btn')}</div>`:'';}
function footer(withRenewals=false) {
  if(withRenewals) return `<div class="limit-footer with-renewals"><div class="limits-inline"><div class="limit-summary"><span><span class="mark">✳</span> Claude <b>98%</b> livre</span><span class="renewal" title="Limite da sessão Claude renova em 3 horas e 9 minutos">↻ 3h 09m</span></div><div class="limit-summary ${critical()?'critical':''}"><span><span class="mark codex">◈</span> Codex <b>${codexRemaining()}%</b> livre</span><span class="renewal" title="Limite da sessão Codex renova em 1 hora e 14 minutos">↻ 1h 14m</span></div></div><button class="usage-icon" data-action="capacity" aria-label="Abrir limites e uso" title="Limites e uso"><svg viewBox="0 0 24 24" width="17" height="17" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 18a9 9 0 1 1 16 0"/><path d="m12 12 4-4M5 15h1M6.5 7.5l1 1M12 4v1M18 15h1"/><circle cx="12" cy="12" r="1.5"/></svg></button></div>`;
  return `<div class="limit-footer"><div class="limits-inline"><span><span class="mark">✳</span> Claude <b>98%</b> livre</span><span class="${critical()?'critical':''}"><span class="mark codex">◈</span> Codex <b>${codexRemaining()}%</b> livre</span></div>${button('Limites e uso','capacity','','text-btn')}</div>`;
}
function approval(s, compact=false) {
  if(compact) return `<div class="inline-action"><p>Permitir Bash? <code>./build.sh --test-suite=agents</code></p><div class="actions">${button('Permitir uma vez','approve',`data-id="${s.id}"`,'pill-btn approve')}${button('Negar','deny',`data-id="${s.id}"`)}${button('Ver contexto','detail',`data-id="${s.id}"`,'text-btn')}</div></div>`;
  return `<article class="attention-card"><div class="eyeline">${mark(s)}<span>${s.provider}</span><span>${escapeHTML(s.project)}</span><span class="push">${s.elapsed}</span></div><h3>Claude precisa de permissão</h3><p class="sub">${escapeHTML(s.topic)} · executar os testes</p><code class="command">./build.sh --test-suite=agents</code><div class="actions">${button('Permitir uma vez','approve',`data-id="${s.id}"`,'pill-btn approve')}${button('Negar','deny',`data-id="${s.id}"`)}${button('Ver conversa','detail',`data-id="${s.id}"`,'text-btn')}</div></article>`;
}
function sessionLine(s) {return `<div class="session-line">${mark(s)}<div class="session-copy"><strong>${escapeHTML(s.project)} / ${escapeHTML(s.topic)}</strong><span class="sub">${escapeHTML(s.activity)}</span></div><div class="sub">${dot(s)} ${statusText(s)}<br>${s.elapsed}</div>${button('›','detail',`data-id="${s.id}" aria-label="Abrir ${escapeHTML(s.topic)}"`,'chevron')}</div>`;}
function periodSelect() {return `<label class="sub">Período <select data-control="period" aria-label="Período de consumo">${['Hoje','Semana','Mês'].map(p=>`<option ${state.period===p?'selected':''}>${p}</option>`).join('')}</select></label>`;}
function usageBody(includeLimits=true) {
  const mult = {Hoje:1,Semana:4.8,Mês:17.5}[state.period];
  return `${includeLimits?`<section class="usage-block"><h4>Limites por conta</h4>${limitsBody()}</section>`:''}
  <section class="usage-block"><h4>Consumo de ${state.period.toLowerCase()}</h4><div class="usage-number">≥ US$ ${(6.95*mult).toLocaleString('pt-BR',{minimumFractionDigits:2,maximumFractionDigits:2})} <small>Valor equivalente de API</small></div><p class="sub">${Math.round(41*mult)}M tokens · 98% vindos de cache</p><p class="sub">Estimativa a preços de API. Não é a fatura da assinatura.</p></section>
  <section class="usage-block"><h4>Tendência</h4><div class="bars" role="img" aria-label="Uso fictício concentrado pela manhã; gráfico do período selecionado">${[5,8,7,12,5,6,14,21,39,85,100,70,48,16,9,4,4,4,4,4,4,4,4,4].map(v=>`<i style="--bar:${v}%"></i>`).join('')}</div><div class="axis"><span>${state.period==='Hoje'?'00h':'Início do período'}</span><span>${state.period==='Hoje'?'12h':''}</span><span>${state.period==='Hoje'?'23h':'Fim do período'}</span></div></section>
  <section class="usage-block split"><div><h4>Modelos</h4><div class="share-line"><span>GPT</span><span>87%</span></div><div class="share-line"><span>Sonnet</span><span>10%</span></div><div class="share-line"><span>Outros</span><span>3%</span></div></div><div><h4>Projetos</h4><div class="share-line"><span>vorssaint-utils</span><span>83%</span></div><div class="share-line"><span>Outros</span><span>17%</span></div></div></section>
  <section class="usage-block"><h4>Atividade histórica</h4><p class="sub">27 dias ativos nas últimas 13 semanas</p><div class="heatmap" role="img" aria-label="Calendário fictício de 13 semanas">${Array.from({length:78},(_,i)=>`<i class="${i%3===0||i%7===1?'active':''}"></i>`).join('')}</div></section>
  <details class="legacy"><summary>Outros provedores</summary><p>OpenCode e Copilot: resumo de uso ao vivo, sem sessões interativas nesta integração.</p></details>`;
}
function limitsBody() {
  return `<div class="account-row"><div class="row between"><h4><span class="mark">✳</span> Claude <span class="sub">Team</span></h4><span>98% livre</span></div><div class="thin-meter claude" style="--value:98%"><i></i></div><p class="sub">Sessão: 98%, renova em 3h 09m · Semana: 100%, em 6d 9h</p></div>
  <div class="account-row"><div class="row between"><h4><span class="mark codex">◈</span> Codex · Padrão <span class="sub">Plus</span></h4><span>${codexRemaining()}% livre</span></div><div class="thin-meter" style="--value:${codexRemaining()}%"><i></i></div><p class="sub">Sessão: ${codexRemaining()}%, renova em 1h 14m · Semana: 89%, em 6d 18h</p><details class="reset-summary"><summary>3 renovações disponíveis · próxima expira em 2 dias</summary><p>Renova os limites de sessão e semana da conta padrão. Nesta simulação, nenhum reset será consumido.</p>${button('Simular renovação','reset-limit','','pill-btn')}</details></div>
  <details class="reset-summary"><summary>Outra conta Codex</summary><div class="account-row"><h4>Codex · Trabalho</h4><div class="thin-meter" style="--value:64%"><i></i></div><p class="sub">Sessão: 64% livre · Semana: 82% livre · conferida há 2 min</p></div></details>`;
}
function capacity() {
  return `<div class="detail-head">${button('‹','back','aria-label="Voltar às sessões"','back')}<strong>Limites e uso</strong>${periodSelect()}</div><div class="capacity-tabs">${button('Limites','capacity-tab','data-tab="limits" aria-pressed="'+(state.capacity==='limits')+'"')}${button('Consumo e histórico','capacity-tab','data-tab="usage" aria-pressed="'+(state.capacity==='usage')+'"')}</div><div class="scroll">${state.capacity==='limits'?limitsBody():usageBody(false)}</div>`;
}
function conversation(s, workspace=false) {
  return `${workspace?`<div class="row between"><h3>${mark(s)} ${s.provider}</h3><span class="sub">${s.elapsed}</span></div><h3>${escapeHTML(s.topic)}</h3><p class="sub">${escapeHTML(s.project)} · ${s.terminal}</p>`:`<div class="detail-head">${button('‹','back','aria-label="Voltar às sessões"','back')}<strong>${escapeHTML(s.topic)}</strong>${mark(s)}<span>${s.provider}</span></div><p class="sub">${escapeHTML(s.project)} · ${s.branch} · ${s.terminal}</p>`}
  <div class="conversation"><p><span class="speaker">Você</span>${s.provider==='Claude'?'Valide a integração das sessões e os avisos de áudio.':'Reorganize os cards priorizando as sessões e pendências.'}</p><p><span class="speaker">${s.provider}</span>${s.pending?'Vou executar a suíte de AI Agents para conferir o comportamento.':escapeHTML(s.activity)+'.'}</p></div>
  ${s.pending?`<div class="attention-card"><h3>Permitir Bash?</h3><code class="command">./build.sh --test-suite=agents</code><div class="actions">${button('Permitir uma vez','approve',`data-id="${s.id}"`,'pill-btn approve')}${button('Negar','deny',`data-id="${s.id}"`)}</div></div>`:`<p class="sub">${dot(s)} ${statusText(s)}</p><form class="reply" data-id="${s.id}"><input aria-label="Resposta para ${s.provider}" placeholder="Responder a ${s.provider}…" autocomplete="off" required><button aria-label="Simular envio">↑</button></form>`}
  <div class="row between" style="margin-top:10px"><span class="sub">${s.model} · ${s.branch}</span>${button('Abrir terminal','terminal',`data-id="${s.id}"`,'text-btn')}</div>`;
}
function VariantA() {
  return `<div class="queue-heading"><h3>${pending()?'Precisa de você':'Suas sessões'}</h3><span>${state.sessions.length} abertas</span></div>${alert()}<div class="scroll queue-list">${state.sessions.length?sessions().map(s=>s.pending?approval(s):sessionLine(s)).join(''):empty()}</div>${footer(true)}`;
}
function VariantB() {
  const tabbar=`<div class="mode-tabs" aria-label="Áreas de AI Agents">${button(`Sessões${pending()?' · '+pending()+' pendente':''}`,'area',`data-area="sessions" aria-pressed="${state.area==='sessions'}"`)}${button('Uso','area',`data-area="usage" aria-pressed="${state.area==='usage'}"`)}</div>`;
  return `${tabbar}${alert()}${state.area==='usage'?`<div class="usage-head"><h3>Uso e disponibilidade</h3>${periodSelect()}</div><div class="scroll usage-destination">${usageBody(true)}</div>`:`<div class="scroll" style="flex:1">${state.sessions.length?sessions().map(s=>`<article class="${s.pending?'pending-row':''}"><div class="table-session"><div class="provider-cell">${mark(s)} ${s.provider}</div><button class="project-cell" data-action="detail" data-id="${s.id}"><strong>${escapeHTML(s.topic)}</strong><span>${escapeHTML(s.project)}</span></button><div class="state-cell">${dot(s)} ${s.pending?'Aguardando':statusText(s)}<br>${s.elapsed}</div></div>${s.pending?approval(s,true):''}</article>`).join(''):empty()}<details class="legacy"><summary>Uso ao vivo de outros provedores</summary><p>OpenCode e Copilot aparecem como resumos; sem sessões interativas.</p></details></div><div class="limit-footer"><span>${pending()?`${pending()} sessão depende de você`:'Nenhuma aprovação pendente'}</span>${button('Consultar limites','capacity','','text-btn')}</div>`}`;
}
function VariantC() {
  const s=selectedSession();
  return `${alert()}<div class="workspace"><div class="scroll session-rail"><h3>${state.sessions.length} sessões</h3>${sessions().map(x=>`<button class="rail-session ${x.pending?'pending':''}" aria-pressed="${s?.id===x.id}" data-action="select" data-id="${x.id}"><span class="row">${mark(x)}<span class="sub">${x.provider}</span>${dot(x)}</span><strong>${escapeHTML(x.topic)}</strong><span class="sub">${escapeHTML(x.project)}</span><span class="sub">${x.pending?'Precisa de você':statusText(x)}</span></button>`).join('')}</div><div class="scroll workspace-detail">${s?conversation(s,true):empty()}</div></div>${footer()}`;
}
function showState() {
  const snapshot={alternativa:state.variant,cenario:state.scenario,largura:state.width,alturaConteudo:320,area:state.area,detalhe:state.detail,selecionada:state.selected,periodo:state.period,pendencias:pending(),sessoes:state.sessions,limites:{claudeLivre:98,codexLivre:codexRemaining(),resets:3},ultimaAcao:state.notice||null,persistencia:false,dados:'fictícios'};
  $('#state').textContent=JSON.stringify(snapshot,null,2);
  // Full state is also surfaced on every variant switch for inspection.
  console.info('AI Agents prototype state',snapshot);
}
function render() {
  const opened = new Set([...$('#surface').querySelectorAll('details[open]')].map(d=>d.querySelector('summary').textContent));
  const v=variants[state.variant];
  $('#variant-key').textContent=state.variant; $('#variant-title').textContent=v.name;
  $('#variant-description').textContent=v.description; $('#variant-gain').textContent=v.gain; $('#variant-tradeoff').textContent=v.tradeoff;
  $('#switch-label').textContent=`${state.variant} · ${v.name}`;
  $('#band-count').textContent=pending()?`${pending()} pendente`:`${state.sessions.length} sessões`;
  $('#island-wrap').style.setProperty('--island-width',`${state.width}px`);
  $('#dimension-label').textContent=`${state.width} px solicitados · conteúdo de 320 px${innerWidth<700?' · ajustado à tela':''}`;
  const detail=state.sessions.find(s=>s.id===state.detail);
  $('#surface').innerHTML=state.area==='capacity'?capacity():detail?`<div class="scroll" style="flex:1">${conversation(detail)}</div>`:({A:VariantA,B:VariantB,C:VariantC}[state.variant])();
  $('#surface').querySelectorAll('details').forEach(d=>{d.open=opened.has(d.querySelector('summary').textContent);});
  if(state.notice) $('#action-status').textContent=state.notice;
  showState();
}
function switchVariant(delta) {
  const keys=Object.keys(variants);state.variant=keys[(keys.indexOf(state.variant)+delta+keys.length)%keys.length];state.area='sessions';state.detail=null;
  const url=new URL(location.href);url.searchParams.set('variant',state.variant);history.replaceState(null,'',url);render();
}
$('#previous').onclick=()=>switchVariant(-1); $('#next').onclick=()=>switchVariant(1);
document.addEventListener('keydown',e=>{if(e.target.closest('input,textarea,select,[contenteditable]'))return;if(e.key==='ArrowLeft'||e.key==='ArrowRight'){e.preventDefault();switchVariant(e.key==='ArrowLeft'?-1:1);}});
function resetScenario() {state.sessions=fixture(state.scenario);state.area='sessions';state.detail=null;state.selected=state.sessions[0]?.id??null;state.notice='Cenário reiniciado. Todas as ações são simuladas.';render();}
$('#scenario').onchange=e=>{state.scenario=e.target.value;resetScenario();};$('#width').onchange=e=>{state.width=Number(e.target.value);render();};$('#reset').onclick=resetScenario;
$('#surface').addEventListener('change',e=>{if(e.target.dataset.control==='period'){state.period=e.target.value;render();}});
$('#surface').addEventListener('click',e=>{
  const target=e.target.closest('[data-action]');if(!target)return;
  const {action,id}=target.dataset;
  const s=state.sessions.find(x=>x.id===id);
  if(action==='approve'||action==='deny') {Object.assign(s,{pending:false,status:action==='approve'?'working':'waiting',activity:action==='approve'?'Executando os testes de AI Agents':'Permissão negada; aguardando orientação'});state.notice=action==='approve'?'Simulação: Claude recebeu permissão uma vez. Nenhum comando foi executado.':'Simulação: permissão negada. Nenhuma tecla foi enviada ao terminal.';}
  if(action==='detail'){state.detail=id;state.selected=id;}
  if(action==='select'){state.selected=id;}
  if(action==='back'){state.area='sessions';state.detail=null;}
  if(action==='area'){state.area=target.dataset.area;state.detail=null;}
  if(action==='capacity'){state.area='capacity';state.capacity='limits';state.detail=null;}
  if(action==='capacity-tab'){state.capacity=target.dataset.tab;}
  if(action==='reset-limit'){state.notice='Simulação de renovação selecionada. Nenhum reset real foi consumido.';}
  if(action==='terminal'){state.notice=`Simulação: abriria o terminal de “${s.topic}”. Nenhum aplicativo foi acionado.`;}
  render();
});
$('#surface').addEventListener('submit',e=>{e.preventDefault();const input=e.target.querySelector('input');const s=state.sessions.find(x=>x.id===e.target.dataset.id);if(!input.value.trim()||!s)return;Object.assign(s,{status:'working',activity:'Respondendo à mensagem simulada'});state.notice=`Simulação: mensagem para ${s.provider} em “${s.topic}”. Não foi enviada a nenhum serviço.`;render();});
// Local preview only. These files are never referenced by the native build.
$('#switcher').hidden=!(location.protocol==='file:'||['localhost','127.0.0.1','::1'].includes(location.hostname));
state.sessions=fixture(state.scenario);render();
