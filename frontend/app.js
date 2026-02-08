let socket;
let myName = "";
let joined = false;

document.addEventListener("DOMContentLoaded", () => {

  const nameBox = document.getElementById("username");
  const joinBtn = document.getElementById("joinBtn");
  const msgBox = document.getElementById("msgBox");
  const msgArea = document.getElementById("messages");
  const usersBox = document.getElementById("users");

  msgBox.disabled = true;

  const proto = location.protocol === "https:" ? "wss" : "ws";
  socket = new WebSocket(`${proto}://${location.host}/ws`);

  socket.onmessage = e => {
    const data = JSON.parse(e.data);

    if (data.type === "message") addMsg(data.user, data.text);
    if (data.type === "users") showUsers(data.users);
  };

  joinBtn.onclick = () => {
    if (socket.readyState !== 1) return;

    myName = nameBox.value.trim();
    if (!myName) return;

    socket.send(JSON.stringify({
      type: "join",
      user: myName
    }));

    joined = true;
    nameBox.disabled = true;
    joinBtn.disabled = true;

    msgBox.disabled = false;
    msgBox.focus();
  };

  nameBox.addEventListener("keydown", e => {
    if (e.key === "Enter") joinBtn.click();
  });

  msgBox.addEventListener("keydown", e => {
    if (!joined) return;

    if (e.key === "Enter") {
      const text = msgBox.value.trim();
      if (!text) return;

      socket.send(JSON.stringify({
        type: "message",
        user: myName,
        text: text
      }));

      msgBox.value = "";
    }
  });

  function addMsg(user, text) {
    const d = document.createElement("div");

    if (user === myName) {
      d.className = "msg me";
    } else {
      d.className = "msg other";
    }

    d.innerHTML = `<span class="name">${user}</span>${text}`;

    msgArea.appendChild(d);
    msgArea.scrollTop = msgArea.scrollHeight;
  }

  function showUsers(list) {
    usersBox.innerHTML = "";

    list.forEach(name => {
      const d = document.createElement("div");
      d.textContent = name;
      usersBox.appendChild(d);
    });
  }

});

