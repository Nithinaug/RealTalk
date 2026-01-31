let ws;
let username="";
let joined=false;

document.addEventListener("DOMContentLoaded",()=>{

const u=document.getElementById("username");
const j=document.getElementById("joinBtn");
const m=document.getElementById("msgBox");
const msgs=document.getElementById("messages");
const usersDiv=document.getElementById("users");

m.disabled=true;

const p=location.protocol==="https:"?"wss":"ws";
ws=new WebSocket(`${p}://${location.host}/ws`);

ws.onmessage=e=>{
const msg=JSON.parse(e.data);

if(msg.type==="message") addMsg(msg.user,msg.text);
if(msg.type==="users") showUsers(msg.users);
};

j.onclick=()=>{
if(ws.readyState!==1) return;

username=u.value.trim();
if(!username) return;

ws.send(JSON.stringify({
type:"join",
user:username
}));

joined=true;
u.disabled=true;
j.disabled=true;

m.disabled=false;
m.focus();
};

u.addEventListener("keydown",e=>{
if(e.key==="Enter") j.click();
});

m.addEventListener("keydown",e=>{
if(!joined) return;

if(e.key==="Enter"){
const t=m.value.trim();
if(!t) return;

ws.send(JSON.stringify({
type:"message",
user:username,
text:t
}));

m.value="";
}
});

function addMsg(user,text){
const d=document.createElement("div");

if(user===username){
d.className="msg me";
}else{
d.className="msg other";
}

d.innerHTML=`<span class="name">${user}</span>${text}`;

msgs.appendChild(d);
msgs.scrollTop=msgs.scrollHeight;
}


function showUsers(list){
usersDiv.innerHTML="";
list.forEach(x=>{
const d=document.createElement("div");
d.textContent=x;
usersDiv.appendChild(d);
});
}

});
