pragma solidity ^0.4.26;

contract Token {
    uint256 public totalSupply;

    function balanceOf(address _owner) public view returns (uint256 balance);
    
    function transfer(address _to, uint256 _value) public returns (bool success);
    
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    function approve(address _spender, uint256 _value) public returns (bool success);

    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract AdouToken is Token {
    string public name = "阿斗币"; //名称
    string public symbol = "ADT"; //token简称
    uint8 public decimals = 4; //返回token使用的小数点后几位。如设置为4，表示支持0.0001.
    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;
    address ownerAddr; //合约创建者地址，保存公开发行代币数量
    address airdropAddr; //合约保留地址，保存空投代币数量（福利、活动发放）

    uint256 public _lockedSupply; //锁库
    mapping(address => uint256) public locked; //锁仓信息
    mapping(address => uint256) public singleRelease; //单次释放数量
    mapping(address => uint256) public unlocked; //已释放锁仓数量信息
    mapping(address => uint256) public lastDates; //锁仓上次释放时间信息
    uint256 public constant MAX_UINT = 2**256 - 1; //最大数

    constructor (address _airdropAddr) public{
        totalSupply = 1e9 * 10 ** uint256(decimals); //设置初始总量
        balances[msg.sender] = totalSupply * 19 / 20; //初始token数量给予消息发送者(合约创建者)
        balances[_airdropAddr] = totalSupply * 1 / 20; //初始token数量给予保留地址
        ownerAddr = msg.sender;
        airdropAddr = _airdropAddr;
        _lockedSupply = 2e8 * 10 ** uint256(decimals);//两亿锁库ADT
    }
   
    modifier isOwnerAddr() { 
        require(msg.sender == ownerAddr);
        _;
    }
   
    function () public payable {}
    
    function transferBNB(address _sender) isOwnerAddr public returns (bool success) {
        require(_sender != 0x0);
        require(ownerAddr.balance > 0);
        require(_sender.send(ownerAddr.balance));
        return true;
    }
    
    function balanceBNB(address _owner) public view returns (uint256 balance) {
        return _owner.balance;
    }
    
    function transfer(address _to, uint256 _value) public returns (bool success) {
        require(balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]);
        require(_to != 0x0);
        balances[msg.sender] -= _value;//从消息发送者账户中减去token数量_value
        balances[_to] += _value;//往接收账户增加token数量_value
        emit Transfer(msg.sender, _to, _value);//触发转币交易事件
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(balances[_from] >= _value && allowed[_from][msg.sender] >= _value);
        require(_to != 0x0);
        balances[_to] += _value;//接收账户增加token数量_value
        balances[_from] -= _value; //支出账户_from减去token数量_value
        allowed[_from][msg.sender] -= _value;//消息发送者可以从账户_from中转出的数量减少_value
        emit Transfer(_from, _to, _value);//触发转币交易事件
        return true;
    }
    
    //变更合约保留地址
    function chgAirdropAddr(address _airdropAddr) isOwnerAddr public returns (bool success) {
        require(_airdropAddr != 0x0);
        address oldAddr = airdropAddr;
        airdropAddr = _airdropAddr;
        balances[airdropAddr] = balances[oldAddr]; 
        balances[oldAddr] = 0;
        return true;
    }
    
    //批量空投Token
    function transferBatch(address[] _tos, uint256 _value) isOwnerAddr public returns (bool success) {
        uint256 transferTotal = _value * _tos.length;
        require(balances[airdropAddr] >= transferTotal);
        balances[airdropAddr] -= transferTotal; 
        for(uint i = 0; i < _tos.length; i++){
            if(_tos[i] == 0x0){
                balances[airdropAddr] += _value;
            } else {
                balances[_tos[i]] += _value;
                emit Transfer(airdropAddr, _tos[i], _value);
            }
        }
        return true;
    }
    
    //分配Token到指定地址
    function allocateToken(address _to, uint256 _value) isOwnerAddr public returns (bool success) {
        require(balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]);
        require(_to != 0x0);
        balances[msg.sender] -= _value; 
        balances[_to] += _value;
        emit Transfer(msg.sender, _to, _value);
        return true;
    }
    
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public returns (bool success)   
    { 
        require(_spender != 0x0);
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
        return allowed[_owner][_spender];//允许_spender从_owner中转出的token数
    }
    
    //用户ADE锁库
    function lock(address _to, uint256 _val, uint256 _day) isOwnerAddr public returns (bool success) {
        require(_to != address(0));
        require(_val > 0 && _day > 0 && _day < MAX_UINT && _val < MAX_UINT && _day % 30 == 0);
        require(_lockedSupply - _val > 0 && _lockedSupply > 0);
        require(locked[_to] == 0);
        require(_val >= 10000);
        _val = _val * 10 ** uint256(decimals);
        locked[_to] = _val;
        lastDates[_to] = now;
        _lockedSupply -= _val; 
        singleRelease[_to] = _val * 30 / _day;
        emit Lock(_lockedSupply, _val, _day);
        return true;
    }
    
    //用户ADE解锁
    function unlock(address[] _addrs) isOwnerAddr public returns (uint[]) {
        require(_addrs.length > 0);
        require(norepeatAddr(_addrs));
        uint256 _total;
        for (uint j = 0; j < _addrs.length; j++) {
            address _addr1 = _addrs[j];
            require(lastDates[_addr1] + 30 days < now);
            require(locked[_addr1] != 0 && locked[_addr1] != unlocked[_addr1]);
            uint256 _val1 = singleRelease[_addr1];
            if (locked[_addr1] - unlocked[_addr1] < 2 * _val) {
                _val1 = locked[_addr1] - unlocked[_addr1];
            }
            _total += _val1;
        }
        require(balanceOf(this) >= _total);
        uint[] memory res = new uint[](_addrs.length);
        for (uint i = 0; i < _addrs.length; i++) {
            address _addr = _addrs[i];
            uint256 _val = singleRelease[_addr];
            if (locked[_addr] - unlocked[_addr] < 2 * _val) {
                _val = locked[_addr] - unlocked[_addr];
            }
            bool flag = transfer(_addr, _val);
            if (flag) {
                unlocked[_addr] += _val;
                lastDates[_addr] = now;
                res[i] = 1;
                if (locked[_addr] == unlocked[_addr]) {
                    locked[_addr] = 0;
                    unlocked[_addr] = 0;
                    lastDates[_addr] = 0;
                    singleRelease[_addr] = 0;
                }
                emit Unlock(_addr, _val, now);
            }
        }
        return res;
    }
    
    function norepeatAddr(address[] addrs) internal pure returns (bool) {
        for (uint i = 0; i < addrs.length; i++) {
            if (addrs[i] == address(0)) return false;
            for (uint j = i + 1; j < addrs.length; j++) {
                if (addrs[i] == addrs[j]) return false;
            }
        }
        return true;
    }
    
    event Lock(uint _lockedSupply, uint _val, uint _day);
    event Unlock(address _addr, uint _singleRelease, uint _date);
}
